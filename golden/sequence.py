"""Golden model for one SSM timestep, expressed purely as FMA ops.

The unit computes a diagonal complex state-space step:

    x[k] = Lambda * x[k-1] + B @ u[k] + b       (Lambda diagonal, complex)
    y[k] = ReLU( Re{C @ x[k]} + c ) + u[k]      (real output, skip connection)

Every arithmetic operation in that is of the form  +/- a*b + acc, so the whole
timestep maps onto the single posit FMA port in src/fma with nothing else in
the datapath.
"""

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
