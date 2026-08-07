"""Golden model for one SSM timestep, expressed purely as FMA ops.

The unit computes a diagonal complex state-space step:

    x[k] = Lambda * x[k-1] + B @ u[k] + b       (Lambda diagonal, complex)
    y[k] = ReLU( Re{C @ x[k]} + c ) + u[k]      (real output, skip connection)

Every arithmetic operation in that is of the form  +/- a*b + acc, so the whole
timestep maps onto the single posit FMA port in src/fma with nothing else in
the datapath.
"""

import os
from bisect import bisect_left
from dataclasses import dataclass
from fractions import Fraction

import numpy as np


def fma(mul1: np.uint8, mul2: np.uint8, add: np.uint8) -> np.uint8:
   return mul1 * mul2 + add


# ---------------------------------------------------------------------------
# Op trace: every FMA the datapath issues, in order, for the RTL testbench.
# ---------------------------------------------------------------------------
TRACE = []


def issue(dst: str, mul1, mul2, add, expr: str):
   """Run one FMA on the datapath and record it."""
   result = fma(mul1, mul2, add)
   TRACE.append({"n": len(TRACE), "dst": dst, "expr": expr,
                 "mul1": float(mul1), "mul2": float(mul2),
                 "add": float(add), "result": float(result)})
   return result


class Complex_Num:
   def __init__(self, a, b):
       self.R = a
       self.C = b


class DataStream:
   # Streamed from External
   def __init__(self, n_inout: int = 4, n_hidden: int = 8):
       self.lambda_ = Complex_Num(np.zeros(n_hidden),
                                  np.zeros(n_hidden))
       self.B_matrix = Complex_Num(np.zeros((n_hidden, n_inout)),
                                   np.zeros((n_hidden, n_inout)))
       self.C_matrix = Complex_Num(np.zeros((n_inout, n_hidden)),
                                   np.zeros((n_inout, n_hidden)))
       self.b_bias = Complex_Num(np.zeros(n_hidden),
                                 np.zeros(n_hidden))
       self.c_bias = Complex_Num(np.zeros(n_inout),
                                 np.zeros(n_inout))

   def set_unit(self, name: str, value: np.ndarray):
       setattr(self, name, value)

   def get_unit(self, name: str, value: np.ndarray):
       getattr(self, name, value)


class InternalStorage:
   # FF within the Unit
   def __init__(self, n_inout: int = 4, n_hidden: int = 8):
       self.x_state = Complex_Num(np.zeros(n_hidden),
                                  np.zeros(n_hidden))
       self.u_data = np.zeros(n_inout)
       self.acc = 0.0

       self.x_int = Complex_Num(0.0, 0.0)

   def set_unit(self, name: str, value: np.ndarray):
       setattr(self, name, value)

   def get_unit(self, name: str, value: np.ndarray):
       getattr(self, name, value)


def procedure(DS: DataStream, IS: InternalStorage):
   """Readable spec of one timestep. sequence() must match this exactly."""

   n_hidden = IS.x_state.R.size
   n_inout = IS.u_data.size

   # internal state from k-1
   x_array = IS.x_state

   # input vector (real)
   u_k = IS.u_data

   x_k = Complex_Num(np.zeros(n_hidden), np.zeros(n_hidden))
   y_k = np.zeros(n_inout)

   # ------------------------------------------------------
   # [1] Update internal state x_k
   # ------------------------------------------------------
   for i in range(n_hidden):
       x_i_k = Complex_Num(0.0, 0.0)

       # ---------- Real Part -----------
       # Lambda * x_i[k-1] => R*R - C*C for complex numbers
       x_i_k.R += x_array.R[i] * DS.lambda_.R[i]
       x_i_k.R += - x_array.C[i] * DS.lambda_.C[i]

       # Loop over B items
       for j in range(n_inout):
           x_i_k.R += DS.B_matrix.R[i, j] * u_k[j]

       # Add b bias
       x_i_k.R += DS.b_bias.R[i]

       # ---------- Complex Part -----------
       # Lambda * x_i[k-1] => R*C + C*R for complex numbers
       x_i_k.C += x_array.R[i] * DS.lambda_.C[i]
       x_i_k.C += x_array.C[i] * DS.lambda_.R[i]

       # Loop over B items
       for j in range(n_inout):
           x_i_k.C += DS.B_matrix.C[i, j] * u_k[j]

       # Add b bias
       x_i_k.C += DS.b_bias.C[i]

       x_k.R[i] = x_i_k.R
       x_k.C[i] = x_i_k.C

   # ------------------------------------------------------
   # Compute output y_k
   # ------------------------------------------------------
   for i in range(n_inout):
       y_i_k = 0.0

       # ---------- Real Part -----------
       # Only Re{C x} leaves the unit, so no imaginary accumulator is built.
       for j in range(n_hidden):
           y_i_k += DS.C_matrix.R[i, j] * x_k.R[j]
           y_i_k += - DS.C_matrix.C[i, j] * x_k.C[j]

       # Add c bias
       y_i_k += DS.c_bias.R[i]

       # ReLU + Skip layer
       y_k[i] = u_k[i] + y_i_k if y_i_k > 0 else 0.0

   IS.x_state = x_k
   return x_k, y_k


# ---------------------------------------------------------------------------
# The same timestep as a flat sequence of FMA ops.
#
# Register file:  x_state.R[H], x_state.C[H], u_data[U]   (state / input)
#                 x_int.R, x_int.C                        (state accumulator)
#                 acc                                     (output accumulator)
#
# Rules used to get everything onto the single FMA port:
#   * subtraction -> negate one multiplicand (posit negate = 2's complement)
#   * bias        -> seeds the `add` port of the FIRST op in a chain, free
#   * skip layer  -> fma(1, u[i], acc)
#   * ReLU        -> not an FMA: the sign bit of the posit accumulator selects
#                    the result or zero. Issued unconditionally so the
#                    schedule length stays data independent.
#
# Op count: 2*H*(U + 2) + U*(2*H + 1)      # H=4, U=2 -> 50
# ---------------------------------------------------------------------------
def sequence(DS: DataStream, IS: InternalStorage):

   H = IS.x_state.R.size
   U = IS.u_data.size
   y = np.zeros(U)

   # ------------------------------------------------------
   # [1] Update internal state x_k
   #
   # Lambda is diagonal, so x[k][i] depends only on x[k-1][i] and the state
   # can be updated in place. Both accumulators must be filled before the
   # commit though, since x_int.C still reads the OLD x_state[i].
   # ------------------------------------------------------
   for i in range(H):

       # ---------- Real Part: Re{lambda*x} = R*R - C*C ----------
       IS.x_int.R = issue("x_int.R", DS.lambda_.R[i], IS.x_state.R[i],
                          DS.b_bias.R[i], f"lambda.R[{i}]*x.R[{i}] + b.R[{i}]")
       IS.x_int.R = issue("x_int.R", -DS.lambda_.C[i], IS.x_state.C[i],
                          IS.x_int.R, f"-lambda.C[{i}]*x.C[{i}] + x_int.R")
       for j in range(U):
           IS.x_int.R = issue("x_int.R", DS.B_matrix.R[i, j], IS.u_data[j],
                              IS.x_int.R, f"B.R[{i},{j}]*u[{j}] + x_int.R")

       # ---------- Complex Part: Im{lambda*x} = R*C + C*R ----------
       IS.x_int.C = issue("x_int.C", DS.lambda_.C[i], IS.x_state.R[i],
                          DS.b_bias.C[i], f"lambda.C[{i}]*x.R[{i}] + b.C[{i}]")
       IS.x_int.C = issue("x_int.C", DS.lambda_.R[i], IS.x_state.C[i],
                          IS.x_int.C, f"lambda.R[{i}]*x.C[{i}] + x_int.C")
       for j in range(U):
           IS.x_int.C = issue("x_int.C", DS.B_matrix.C[i, j], IS.u_data[j],
                              IS.x_int.C, f"B.C[{i},{j}]*u[{j}] + x_int.C")

       # commit x_int -> x_state[i]
       IS.x_state.R[i] = IS.x_int.R
       IS.x_state.C[i] = IS.x_int.C

   # ------------------------------------------------------
   # [2] Compute output y_k = ReLU(Re{C x[k]} + c) + u
   # ------------------------------------------------------
   for i in range(U):

       IS.acc = issue("acc", DS.C_matrix.R[i, 0], IS.x_state.R[0],
                      DS.c_bias.R[i], f"C.R[{i},0]*x.R[0] + c.R[{i}]")
       IS.acc = issue("acc", -DS.C_matrix.C[i, 0], IS.x_state.C[0],
                      IS.acc, f"-C.C[{i},0]*x.C[0] + acc")
       for j in range(1, H):
           IS.acc = issue("acc", DS.C_matrix.R[i, j], IS.x_state.R[j],
                          IS.acc, f"C.R[{i},{j}]*x.R[{j}] + acc")
           IS.acc = issue("acc", -DS.C_matrix.C[i, j], IS.x_state.C[j],
                          IS.acc, f"-C.C[{i},{j}]*x.C[{j}] + acc")

       # Skip layer on the FMA port, then ReLU as a sign-bit select.
       skip = issue(f"y[{i}]", 1.0, IS.u_data[i], IS.acc, f"1*u[{i}] + acc")
       y[i] = skip if IS.acc > 0 else 0.0

   return IS.x_state, y


def reference(DS: DataStream, x_prev, u_k):
   """numpy complex reference, independent of both implementations above."""
   lam = DS.lambda_.R + 1j * DS.lambda_.C
   B = DS.B_matrix.R + 1j * DS.B_matrix.C
   C = DS.C_matrix.R + 1j * DS.C_matrix.C
   b = DS.b_bias.R + 1j * DS.b_bias.C

   x = lam * x_prev + B @ u_k + b
   pre = np.real(C @ x) + DS.c_bias.R
   y = np.where(pre > 0, u_k + pre, 0.0)
   return x, y


def random_stream(n_inout, n_hidden, seed=0):
   rng = np.random.default_rng(seed)
   DS = DataStream(n_inout=n_inout, n_hidden=n_hidden)
   DS.lambda_ = Complex_Num(rng.uniform(-1, 1, n_hidden),
                             rng.uniform(-1, 1, n_hidden))
   DS.B_matrix = Complex_Num(rng.uniform(-1, 1, (n_hidden, n_inout)),
                             rng.uniform(-1, 1, (n_hidden, n_inout)))
   DS.C_matrix = Complex_Num(rng.uniform(-1, 1, (n_inout, n_hidden)),
                             rng.uniform(-1, 1, (n_inout, n_hidden)))
   DS.b_bias = Complex_Num(rng.uniform(-1, 1, n_hidden),
                           rng.uniform(-1, 1, n_hidden))
   DS.c_bias = Complex_Num(rng.uniform(-1, 1, n_inout),
                           rng.uniform(-1, 1, n_inout))
   return DS, rng


def _block(label: str, arr: np.ndarray, indent: str = "    "):
   """Format one array under a label, every row indented the same amount."""
   with np.printoptions(precision=6, suppress=True, floatmode="fixed"):
       text = np.array2string(np.atleast_1d(np.asarray(arr)))
   body = "\n".join(indent + line for line in text.splitlines())
   return f"  {label} =\n{body}"


def show_complex(name: str, cn: Complex_Num):
   """Print one complex operand: shape, then real/imag contents."""
   shape = np.shape(cn.R)
   kind = "vector" if len(shape) == 1 else "matrix"
   print(f"{name:<10} {kind:<6} shape {str(shape):<8} "
         f"({np.size(cn.R)} complex elements)")
   print(_block("Re", cn.R))
   print(_block("Im", cn.C))
   print()


def show_real(name: str, arr: np.ndarray):
   """Print one purely real operand: shape, then contents."""
   arr = np.asarray(arr)
   kind = "vector" if arr.ndim == 1 else "matrix"
   print(f"{name:<10} {kind:<6} shape {str(arr.shape):<8} "
         f"({arr.size} real elements)")
   print(_block("val", arr))
   print()


def dump_stream(DS: DataStream, x_init: Complex_Num, u_all: np.ndarray,
                n_inout: int, n_hidden: int, n_steps: int):
   """Dump every matrix/vector fed into the run, with its size."""
   print("=" * 70)
   print(f"operands   n_inout (U) = {n_inout}   n_hidden (H) = {n_hidden}   "
         f"timesteps (K) = {n_steps}")
   print("=" * 70)
   show_complex("lambda_", DS.lambda_)       # (H,)   diagonal state matrix
   show_complex("B_matrix", DS.B_matrix)     # (H, U) input matrix
   show_complex("C_matrix", DS.C_matrix)     # (U, H) output matrix
   show_complex("b_bias", DS.b_bias)         # (H,)   state bias
   show_complex("c_bias", DS.c_bias)         # (U,)   output bias (Re used)
   show_complex("x[-1]", x_init)             # (H,)   state before k=0
   show_real("u[0..K-1]", u_all)             # (K, U) one input vector per step
   print("=" * 70 + "\n")


# ===========================================================================
# posit(8,2) -- the number format on the FMA port and therefore on the wire.
#
# src/fma/fma.vhd is decode -> multiply -> add -> encode with a single rounding
# in the encoder (round to nearest even: guard and (lsb or sticky)). So one FMA
# is  round( a*b + c )  evaluated exactly and rounded once, which is what
# posit_fma() below does with Fraction arithmetic.
# ===========================================================================
POSIT_N = 8
POSIT_ES = 2

POSIT_ZERO = 0x00
POSIT_NAR = 0x80
POSIT_ONE = 0x40      # matches localparam POSIT_ONE in src/fsm/fsm.v


def posit_decode(bits: int) -> Fraction:
   """Exact value of one posit byte. NaR decodes as None."""
   bits &= 0xFF
   if bits == POSIT_ZERO:
      return Fraction(0)
   if bits == POSIT_NAR:
      return None

   sign = bits >> 7
   if sign:
      bits = (-bits) & 0xFF                       # posit negate = 2's complement

   body = format(bits & 0x7F, "07b")

   # regime: run of equal bits, terminated by the opposite bit (or the word end)
   lead = body[0]
   k = 0
   while k < len(body) and body[k] == lead:
      k += 1
   regime = (k - 1) if lead == "1" else -k

   rest = body[k + 1:]                            # skip the terminator bit
   exp_bits = rest[:POSIT_ES].ljust(POSIT_ES, "0")   # bits pushed off are zero
   frac_bits = rest[POSIT_ES:]

   exp = int(exp_bits, 2)
   frac = Fraction(int(frac_bits, 2), 1 << len(frac_bits)) if frac_bits else Fraction(0)

   scale = (1 << POSIT_ES) * regime + exp         # useed^regime * 2^exp
   value = (1 + frac) * Fraction(2) ** scale
   return -value if sign else value


# every positive pattern, ascending: minpos (0x01) .. maxpos (0x7f)
_POS_PATTERNS = list(range(0x01, 0x80))
_POS_VALUES = [posit_decode(b) for b in _POS_PATTERNS]

POSIT_MINPOS = _POS_VALUES[0]
POSIT_MAXPOS = _POS_VALUES[-1]


def posit_encode(value) -> int:
   """Round a real value to a posit byte, nearest with ties to even.

   Posits saturate instead of overflowing and never round a non-zero value to
   zero, so the magnitude is clamped to [minpos, maxpos] before rounding.
   """
   if value is None:
      return POSIT_NAR
   if not isinstance(value, Fraction):
      value = Fraction(float(value))       # exact: floats are binary rationals
   if value == 0:
      return POSIT_ZERO

   sign = value < 0
   mag = -value if sign else value

   if mag >= POSIT_MAXPOS:
      bits = _POS_PATTERNS[-1]
   elif mag <= POSIT_MINPOS:
      bits = _POS_PATTERNS[0]
   else:
      hi = bisect_left(_POS_VALUES, mag)
      if _POS_VALUES[hi] == mag:
         bits = _POS_PATTERNS[hi]
      else:
         lo = hi - 1
         d_lo = mag - _POS_VALUES[lo]
         d_hi = _POS_VALUES[hi] - mag
         if d_lo < d_hi:
            bits = _POS_PATTERNS[lo]
         elif d_hi < d_lo:
            bits = _POS_PATTERNS[hi]
         else:
            bits = _POS_PATTERNS[lo] if _POS_PATTERNS[lo] % 2 == 0 \
               else _POS_PATTERNS[hi]

   return ((-bits) & 0xFF) if sign else bits


def posit_neg(bits: int) -> int:
   """Negate a posit byte. Two's complement, exactly as the host must do it."""
   return (-(bits & 0xFF)) & 0xFF


def posit_fma(a: int, b: int, c: int) -> int:
   """One FMA port evaluation: round(a*b + c), a single rounding."""
   va, vb, vc = posit_decode(a), posit_decode(b), posit_decode(c)
   if va is None or vb is None or vc is None:
      return POSIT_NAR
   return posit_encode(va * vb + vc)


def posit_gt_zero(bits: int) -> bool:
   """The gate condition, as fsm.v computes it: ~acc[7] & |acc[6:0]."""
   return (bits & 0x80) == 0 and (bits & 0x7F) != 0


# ===========================================================================
# Stream vectors
#
# One frame == one timestep. Lanes are positional and there are no addresses,
# so the beat order below IS the contract with src/fsm/fsm.v -- it must stay
# identical to the issue order in sequence() above. cross_check_vectors()
# enforces that by replaying the beats against sequence()'s own TRACE.
#
#   lane 0 -> fma_opa   a weight, absent only on the skip op (opa = 1.0)
#   lane 1 -> fma_opc   at a chain head (a bias)
#          -> fma_opb   on a u-consuming op
#   s_mask   bit0 = lane 0 present, bit1 = lane 1 present
#
# Subtraction is host side: a term used negated is streamed already negated,
# which costs it its own beat (lam.R/lam.C each go out twice per hidden state).
# ===========================================================================
MASK_OP1 = 0b01      # lane 0 only
MASK_BOTH = 0b11     # lane 0 + lane 1
MASK_OP2 = 0b10      # lane 1 only -- the skip op, opa is the constant 1.0


@dataclass
class Beat:
   """One stream beat, with the FMA it drives and the result it must produce."""
   n: int             # beat index within the frame
   mask: int
   op1: int           # lane 0 byte, None when the lane is masked off
   op2: int           # lane 1 byte, None when the lane is masked off
   opa: int           # what the FSM presents on the FMA port ...
   opb: int
   opc: int
   res: int           # ... and what the FMA must return one cycle later
   op2_role: str      # "bias" -> opc, "u" -> opb, None -> lane masked off
   dst: str
   expr: str

   def word(self) -> int:
      """{s_mask[1:0], lane1[7:0], lane0[7:0]} -- one $readmemh token."""
      return (self.mask << 16) | ((self.op2 or 0) << 8) | (self.op1 or 0)

   def wire_bytes(self):
      """The meaningful bytes only, for a byte-serial link upstream of the
      lane splitter. 22 bytes per stage-0 block, 18 per stage-1 block."""
      return [b for b in (self.op1, self.op2) if b is not None]


def frame(DS: DataStream, x_state, u_k, quantise=True):
   """Build one frame of stream beats and evaluate it in posit(8,2).

   DS       weights, as floats (quantise=True) or as posit bytes already
   x_state  (x_R, x_C) posit byte lists, length H each -- state from k-1
   u_k      input vector, floats (quantise=True) or posit bytes

   Returns (beats, y_bytes, x_next) where x_next is the committed state, so
   frames can be chained across timesteps exactly as the FSM does.
   """
   q = posit_encode if quantise else (lambda v: int(v) & 0xFF)

   lam_r = [q(v) for v in np.atleast_1d(DS.lambda_.R)]
   lam_c = [q(v) for v in np.atleast_1d(DS.lambda_.C)]
   b_r = [q(v) for v in np.atleast_1d(DS.b_bias.R)]
   b_c = [q(v) for v in np.atleast_1d(DS.b_bias.C)]
   c_r = [q(v) for v in np.atleast_1d(DS.c_bias.R)]
   B_r = [[q(v) for v in row] for row in np.atleast_2d(DS.B_matrix.R)]
   B_c = [[q(v) for v in row] for row in np.atleast_2d(DS.B_matrix.C)]
   C_r = [[q(v) for v in row] for row in np.atleast_2d(DS.C_matrix.R)]
   C_c = [[q(v) for v in row] for row in np.atleast_2d(DS.C_matrix.C)]
   u = [q(v) for v in np.atleast_1d(u_k)]

   H = len(lam_r)
   U = len(u)

   x_R = list(x_state[0])
   x_C = list(x_state[1])

   beats = []
   y_bytes = []

   def beat(mask, op1, op2, opb, opc, dst, expr, role=None):
      opa = op1 if op1 is not None else POSIT_ONE
      res = posit_fma(opa, opb, opc)
      beats.append(Beat(len(beats), mask, op1, op2, opa, opb, opc, res,
                        role, dst, expr))
      return res

   # ---- stage 0: x[k] = lam*x[k-1] + B@u + b -- 12 beats per hidden state ----
   for i in range(H):

      # Re chain: Re{lam*x} = R*R - C*C, bias seeds the accumulator for free
      x_int_r = beat(MASK_BOTH, lam_r[i], b_r[i], x_R[i], b_r[i],
                     "x_int.R", f"lambda.R[{i}]*x.R[{i}] + b.R[{i}]", "bias")
      x_int_r = beat(MASK_OP1, posit_neg(lam_c[i]), None, x_C[i], x_int_r,
                     "x_int.R", f"-lambda.C[{i}]*x.C[{i}] + x_int.R")
      for j in range(U):
         x_int_r = beat(MASK_BOTH, B_r[i][j], u[j], u[j], x_int_r,
                        "x_int.R", f"B.R[{i},{j}]*u[{j}] + x_int.R", "u")

      # Im chain: Im{lam*x} = R*C + C*R. Still reads the OLD x.R[i], which is
      # why the commit waits until both chains are done.
      x_int_c = beat(MASK_BOTH, lam_c[i], b_c[i], x_R[i], b_c[i],
                     "x_int.C", f"lambda.C[{i}]*x.R[{i}] + b.C[{i}]", "bias")
      x_int_c = beat(MASK_OP1, lam_r[i], None, x_C[i], x_int_c,
                     "x_int.C", f"lambda.R[{i}]*x.C[{i}] + x_int.C")
      for j in range(U):
         x_int_c = beat(MASK_BOTH, B_c[i][j], u[j], u[j], x_int_c,
                        "x_int.C", f"B.C[{i},{j}]*u[{j}] + x_int.C", "u")

      x_R[i] = x_int_r        # commit (2 dead cycles in the FSM, no beats)
      x_C[i] = x_int_c

   # ---- stage 1: y = gate(Re{C@x} + c) + u -- 2H+1 beats per channel --------
   for i in range(U):

      acc = beat(MASK_BOTH, C_r[i][0], c_r[i], x_R[0], c_r[i],
                 "acc", f"C.R[{i},0]*x.R[0] + c.R[{i}]", "bias")
      acc = beat(MASK_OP1, posit_neg(C_c[i][0]), None, x_C[0], acc,
                 "acc", f"-C.C[{i},0]*x.C[0] + acc")
      for j in range(1, H):
         acc = beat(MASK_OP1, C_r[i][j], None, x_R[j], acc,
                    "acc", f"C.R[{i},{j}]*x.R[{j}] + acc")
         acc = beat(MASK_OP1, posit_neg(C_c[i][j]), None, x_C[j], acc,
                    "acc", f"-C.C[{i},{j}]*x.C[{j}] + acc")

      # Skip layer on the FMA port; the gate is on the PRE-skip accumulator but
      # the byte emitted is the POST-skip result. fsm.v:308-310.
      gate = posit_gt_zero(acc)
      skip = beat(MASK_OP2, None, u[i], u[i], acc, f"y[{i}]", f"1*u[{i}] + acc",
                  "u")
      y_bytes.append(skip if gate else POSIT_ZERO)

   return beats, y_bytes, (x_R, x_C)


def cross_check_vectors(beats, DS, x_state, u_k):
   """Replay the beats against sequence()'s TRACE.

   Guards the thing that actually breaks: the beat order drifting away from
   the issue order in sequence(). Only the operands the HOST puts on the wire
   are compared, decoded back to reals -- so this catches a reordered, missing
   or mis-signed beat, but never trips on a rounding difference.
   """
   mark = len(TRACE)

   IS = InternalStorage(n_inout=len(np.atleast_1d(u_k)),
                        n_hidden=len(np.atleast_1d(DS.lambda_.R)))
   IS.x_state = Complex_Num(np.array([float(posit_decode(b)) for b in x_state[0]]),
                            np.array([float(posit_decode(b)) for b in x_state[1]]))
   IS.u_data = np.array([float(posit_decode(posit_encode(v)))
                         for v in np.atleast_1d(u_k)])

   DSq = DataStream(n_inout=IS.u_data.size, n_hidden=IS.x_state.R.size)
   for name in ("lambda_", "B_matrix", "C_matrix", "b_bias", "c_bias"):
      src = getattr(DS, name)
      setattr(DSq, name, Complex_Num(_quantise(src.R), _quantise(src.C)))

   sequence(DSq, IS)
   ops = TRACE[mark:]
   del TRACE[mark:]                      # replay only, do not pollute the trace

   if len(ops) != len(beats):
      return [f"beat count {len(beats)} != op count {len(ops)}"]

   # Only the STREAMED operands are compared. opb from memory and opc from the
   # accumulator are feedback: posit-rounded here, float in sequence(), so they
   # legitimately diverge and checking them would just measure rounding.
   errs = []

   def cmp(beat, label, got, want):
      have = float(posit_decode(got))
      if abs(have - want) > 1e-9:
         errs.append(f"beat {beat.n} ({beat.expr}): {label} {have} != {want}")

   for beat, op in zip(beats, ops):
      if beat.expr != op["expr"]:
         errs.append(f"beat {beat.n}: expr {beat.expr!r} != {op['expr']!r}")
         continue

      cmp(beat, "lane0", beat.opa, op["mul1"])  # weight, or 1.0 on the skip op
      if beat.op2_role == "bias":
         cmp(beat, "lane1(bias)", beat.op2, op["add"])
      elif beat.op2_role == "u":
         cmp(beat, "lane1(u)", beat.op2, op["mul2"])

      # s_mask must agree with the lanes that actually carry data -- this is
      # the same equality the FSM's need_op1/need_op2 must satisfy beat for
      # beat, and the only desync detector on the link.
      want_mask = (1 if beat.op1 is not None else 0) | \
                  (2 if beat.op2 is not None else 0)
      if beat.mask != want_mask:
         errs.append(f"beat {beat.n}: mask {beat.mask:02b} != {want_mask:02b}")

   return errs


def check_mask_pattern(beats, H, U):
   """The mask sequence the host emits is fixed, independent of the data.

   stage 0, per hidden state : 11 01 11*U   twice
   stage 1, per channel      : 11 then (2H-1) x 01 then 10
   """
   want = []
   for _ in range(H):
      for _ in range(2):
         want += [MASK_BOTH, MASK_OP1] + [MASK_BOTH] * U
   for _ in range(U):
      want += [MASK_BOTH] + [MASK_OP1] * (2 * H - 1) + [MASK_OP2]

   got = [b.mask for b in beats]
   if got == want:
      return []
   if len(got) != len(want):
      return [f"mask stream length {len(got)} != {len(want)}"]
   bad = next(i for i, (g, w) in enumerate(zip(got, want)) if g != w)
   return [f"mask stream diverges at beat {bad}: "
           f"{got[bad]:02b} != {want[bad]:02b}"]


def _quantise(arr):
   """Round an array through posit(8,2) and back, so the float model sees the
   same numbers the wire carries."""
   flat = [float(posit_decode(posit_encode(v))) for v in np.asarray(arr).ravel()]
   return np.array(flat).reshape(np.shape(arr))


# ---------------------------------------------------------------------------
# File emission
# ---------------------------------------------------------------------------
def write_vectors(path, DS, x_init, u_all, comments=True, ops=True):
   """Write the stream vectors for K timesteps as $readmemh-able files.

   path is a stem; four files are written next to it:

     <stem>_in.hex     one 18-bit word per beat, {mask, lane1, lane0}
                       -> logic [17:0] vec [0:BEATS*K-1];
     <stem>_y.hex      expected output bytes, U per frame
                       -> logic  [7:0] exp_y [0:U*K-1];
     <stem>_ops.hex    per-beat {opa, opb, opc, res}, 32 bits, for white-box
                       checking of the FMA port    (omit with ops=False)
     <stem>_bytes.hex  the same frames byte-serial, 22*H + 18*U bytes each,
                       for a link upstream of the lane splitter

   Returns a dict of counts.
   """
   H = len(np.atleast_1d(DS.lambda_.R))
   U = len(np.atleast_1d(DS.c_bias.R))
   u_all = np.atleast_2d(u_all)
   K = u_all.shape[0]

   x_state = ([posit_encode(v) for v in np.atleast_1d(x_init.R)],
              [posit_encode(v) for v in np.atleast_1d(x_init.C)])

   all_beats, all_y, errs = [], [], []
   for k in range(K):
      beats, y_bytes, x_next = frame(DS, x_state, u_all[k])
      errs += [f"k={k}: {e}"
               for e in cross_check_vectors(beats, DS, x_state, u_all[k])
               + check_mask_pattern(beats, H, U)]
      all_beats.append(beats)
      all_y.append(y_bytes)
      x_state = x_next            # the FSM carries state across frames too

   beats_per_frame = 12 * H + U * (2 * H + 1)
   bytes_per_frame = 22 * H + 18 * U

   head = (f"// ssm_fsm stream vectors -- generated by golden/sequence.py\n"
           f"// posit({POSIT_N},{POSIT_ES})  H={H}  U={U}  W={POSIT_N}  "
           f"LANES=2  frames={K}\n"
           f"// {beats_per_frame} beats and {bytes_per_frame} operand bytes "
           f"per frame\n")

   os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)

   # ---- stream in ---------------------------------------------------------
   with open(f"{path}_in.hex", "w") as fh:
      fh.write(head)
      fh.write("// {s_mask[1:0], lane1[7:0], lane0[7:0]} -- one word per beat\n")
      for k, beats in enumerate(all_beats):
         fh.write(f"// ---- frame {k} ----\n")
         for b in beats:
            line = f"{b.word():05x}"
            if comments:
               l0 = f"{b.op1:02x}" if b.op1 is not None else "--"
               l1 = f"{b.op2:02x}" if b.op2 is not None else "--"
               line += (f"   // {b.n:3d} mask={b.mask:02b} L0={l0} L1={l1}"
                        f"  {b.expr}")
            fh.write(line + "\n")

   # ---- expected y --------------------------------------------------------
   with open(f"{path}_y.hex", "w") as fh:
      fh.write(head)
      fh.write("// expected y bytes, U per frame, in emission order\n")
      for k, y_bytes in enumerate(all_y):
         for i, yb in enumerate(y_bytes):
            line = f"{yb:02x}"
            if comments:
               line += f"   // frame {k} y[{i}] = {float(posit_decode(yb)):+.6f}"
            fh.write(line + "\n")

   # ---- per-beat FMA port -------------------------------------------------
   if ops:
      with open(f"{path}_ops.hex", "w") as fh:
         fh.write(head)
         fh.write("// {opa[7:0], opb[7:0], opc[7:0], res[7:0]} -- per beat\n")
         for k, beats in enumerate(all_beats):
            fh.write(f"// ---- frame {k} ----\n")
            for b in beats:
               word = (b.opa << 24) | (b.opb << 16) | (b.opc << 8) | b.res
               line = f"{word:08x}"
               if comments:
                  line += f"   // {b.n:3d} {b.dst:<8} {b.expr}"
               fh.write(line + "\n")

   # ---- byte-serial -------------------------------------------------------
   with open(f"{path}_bytes.hex", "w") as fh:
      fh.write(head)
      fh.write("// byte-serial: the meaningful bytes only, mask dropped\n")
      for k, beats in enumerate(all_beats):
         fh.write(f"// ---- frame {k} ----\n")
         for b in beats:
            for byte in b.wire_bytes():
               fh.write(f"{byte:02x}\n")

   n_bytes = sum(len(b.wire_bytes()) for beats in all_beats for b in beats)
   return {"frames": K, "beats_per_frame": beats_per_frame,
           "beats": sum(len(b) for b in all_beats),
           "bytes_per_frame": bytes_per_frame, "bytes": n_bytes,
           "y_bytes": sum(len(y) for y in all_y), "errors": errs}


if __name__ == "__main__":

   # hyper params
   n_inout = 4
   n_hidden = 8
   n_steps = 1          # k = 0 .. 3, state carried across steps

   DS, rng = random_stream(n_inout, n_hidden, seed=1)

   # state before the first timestep, and one input vector per timestep
   x_init = Complex_Num(rng.uniform(-1, 1, n_hidden),
                        rng.uniform(-1, 1, n_hidden))
   u_all = rng.uniform(-1, 1, (n_steps, n_inout))

   dump_stream(DS, x_init, u_all, n_inout, n_hidden, n_steps)

   # Each model keeps its own state and is stepped in lockstep.
   IS = InternalStorage(n_inout=n_inout, n_hidden=n_hidden)
   IS.x_state = Complex_Num(x_init.R.copy(), x_init.C.copy())

   IS2 = InternalStorage(n_inout=n_inout, n_hidden=n_hidden)
   IS2.x_state = Complex_Num(x_init.R.copy(), x_init.C.copy())

   x_ref = x_init.R + 1j * x_init.C

   n_expect = 2 * n_hidden * (n_inout + 2) + n_inout * (2 * n_hidden + 1)
   ok = True

   for k in range(n_steps):
       u_k = u_all[k]
       mark = len(TRACE)

       # --- sequence ------------------------------------------------------
       IS.u_data = u_k.copy()
       x_seq, y_seq = sequence(DS, IS)

       # --- procedure -----------------------------------------------------
       IS2.u_data = u_k.copy()
       x_proc, y_proc = procedure(DS, IS2)

       # --- reference -----------------------------------------------------
       x_ref, y_ref = reference(DS, x_ref, u_k)

       print("-" * 70)
       print(f"k = {k}   u[k] = {np.array2string(u_k, precision=6)}   "
             f"ops {mark}..{len(TRACE) - 1} "
             f"({len(TRACE) - mark}, formula {n_expect})")
       print("-" * 70)
       for op in TRACE[mark:]:
           print(f"  {op['n']:3d}  {op['dst']:<8} = {op['expr']:<34} "
                 f"-> {op['result']:+.6f}")

       match_proc = (np.allclose(x_seq.R, x_proc.R)
                     and np.allclose(x_seq.C, x_proc.C)
                     and np.allclose(y_seq, y_proc))
       match_ref = (np.allclose(x_seq.R, x_ref.real)
                    and np.allclose(x_seq.C, x_ref.imag)
                    and np.allclose(y_seq, y_ref))
       ok = ok and match_proc and match_ref

       print(f"\n  sequence vs procedure : {match_proc}")
       print(f"  sequence vs reference : {match_ref}")
       print(f"  x[{k}] =", x_seq.R + 1j * x_seq.C)
       print(f"  y[{k}] =", y_seq, "\n")

   print("=" * 70)
   print(f"total ops : {len(TRACE)}  ({n_steps} x {n_expect})")
   print(f"all steps match : {ok}")
   print("=" * 70)

   # ---- stream vectors for the RTL testbench ------------------------------
   stem = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "vectors", f"ssm_h{n_hidden}_u{n_inout}")
   info = write_vectors(stem, DS, x_init, u_all)

   print()
   print("=" * 70)
   print(f"vectors : {stem}_{{in,y,ops,bytes}}.hex")
   print(f"  frames        : {info['frames']}")
   print(f"  beats         : {info['beats']}  "
         f"({info['beats_per_frame']}/frame)")
   print(f"  operand bytes : {info['bytes']}  "
         f"({info['bytes_per_frame']}/frame)")
   print(f"  y bytes       : {info['y_bytes']}")
   if info["errors"]:
      print("  CROSS CHECK FAILED vs sequence():")
      for e in info["errors"][:10]:
         print(f"    {e}")
   else:
      print("  cross check vs sequence() TRACE : ok")
   print("=" * 70)
