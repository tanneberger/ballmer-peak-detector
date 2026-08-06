import numpy as np


def fma(mul1: np.uint8, mul2: np.uint8, add:np.uint8) -> np.uint8:
   return mul1 * mul2 + add

 

class DataStream:
   # Streamed from External
   def __init__(self, n_inout: int = 4, n_hidden: int = 8):
       self.lambda_ = Complex_Num(np.zeros((1, n_hidden)),
                                  np.zeros((1, n_hidden)))
       self.B_matrix = Complex_Num(np.zeros((n_hidden, n_inout)),
                                    np.zeros((n_hidden, n_inout)))
       self.C_matrix = Complex_Num(np.zeros((n_inout, n_hidden)),
                                    np.zeros((n_inout, n_hidden)))
       self.b_bias = Complex_Num(np.zeros((1, n_hidden)),
                                  np.zeros((1, n_hidden)))
       self.c_bias = Complex_Num(np.zeros((1, n_inout)),
                                  np.zeros((1, n_inout)))

   def set_unit(self, name: str, value: np.ndarray):
       setattr(self, name, value)

   def get_unit(self, name: str, value: np.ndarray):
       getattr(self, name, value)


class InternalStorage:
   # FF within the Unit
   def __init__(self, n_inout: int = 4, n_hidden: int = 8):
       self.x_state = Complex_Num(np.zeros((1, n_hidden)))
       self.u_data = np.zeros((1, n_inout))
       self.acc = np.zeros(1)

       self.x_int = Complex_Num(np.zeros(1), np.zeros(1))

   def set_unit(self, name: str, value: np.ndarray):
       setattr(self, name, value)

   def get_unit(self, name: str, value: np.ndarray):
       getattr(self, name, value)


class Complex_Num:
   def __init__(self, a, b):
       self.R = a
       self.C = b


def procedure():

   # hyper params
   n_inout = 2
   n_hidden = 4
   DS = DataStream(n_inout=n_inout, n_hidden=n_hidden)

   # init internal state
   x_array = Complex_Num(np.zeros(1, n_hidden), 
                         np.zeros(1, n_hidden))

   # input vector
   u_k = Complex_Num(np.zeros(1, n_inout), 
                         np.zeros(1, n_inout))

   # ------------------------------------------------------
   # [1] Update internal state x_k
   # ------------------------------------------------------
   for i in range(n_hidden):
       x_i_k = Complex_Num(0, 0)

       # ---------- Real Part -----------
       # Lambda * x_i[k-1] => R*R - C*C for complex numbers
       x_i_k.R += x_array.R[i] * DS.lamda.R[i]
       x_i_k.R += - x_array.C[i] * DS.lamda.C[i]

       # Loop over B items
       for j in range(n_inout):
           x_i_k.R += DS.B_matrix.R[i, j] * u_k[i]

       # Add b bias
       x_i_k.R += DS.b_bias.R


       # ---------- Complex Part -----------
       # Lambda * x_i[k-1] => R*C + C*R for complex numbers
       x_i_k.C += x_array.R[i] * DS.lamda.C[i]
       x_i_k.C += x_array.C[i] * DS.lamda.R[i]

       # Loop over B items
       for j in range(n_inout):
           x_i_k.C += DS.B_matrix.C[i, j] * u_k[i]

       # Add b bias
       x_i_k.C += DS.b_bias.C

   # ------------------------------------------------------
   # Compute output y_k
   # ------------------------------------------------------
   for i in range(n_inout):
       y_i_k = Complex_Num(0, 0)

       # ---------- Real Part -----------
       # Loop over C items
       for j in range(n_hidden):
           y_i_k.R += DS.C_matrix.R[i, j] * x_i_k.R[i]
           y_i_k.R += - DS.C_matrix.C[i, j] * x_i_k.C[i]

       # Add b bias
       y_i_k.R += DS.c_bias.R

       # ReLU + Skip layer
       y_i_k.R = u_k[i] + y_i_k.R if y_i_k.R > 0 else 0

       return x_i_k, y_i_k

 

if __name__ == "__main__":

   #sequence
   DS = DataStream              # 
   IS = InternalStorage         # 

    #1) 
    i=0
    IS.x_int.R = fma(mul1=DS.lambda_.R[i], 
                        mul2=IS.x_state.R[i],
                        add=0)

    
    # Either stream -DS.lambda_.C[i] (negative), or add invert instruction
    IS.x_int.R = fma(mul1=DS.lambda_.C[i], 
                    mul2=IS.x_state.C[i],
                    add=IS.x_int.R)

    for j in range(n_inout):
        IS.x_int.R = fma(mul1=DS.B_matrix.R[i, j], 
                        mul2=u_k[i],
                        add=IS.x_int.R)