import numpy as np


def fma(mul1, mul2, add):
    return mul1 * mul2 + add


class DataStream:
    # Streamed from External
    def __init__(self, n_inout: int = 4, n_hidden: int = 8):
        self.lambda_v = Complex_Num(np.zeros((1, n_hidden)),
                                  np.zeros((1, n_hidden)))
        self.B_matrix = Complex_Num(np.zeros((n_hidden, n_inout)),
                                     np.zeros((n_hidden, n_inout)))
        self.C_matrix = Complex_Num(np.zeros((n_inout, n_hidden)),
                                     np.zeros((n_inout, n_hidden)))
        self.b_bias = Complex_Num(np.zeros((1, n_hidden)),
                                   np.zeros((1, n_hidden)))
        self.c_bias = Complex_Num(np.zeros((1, n_inout)),
                                   np.zeros((1, n_inout)))
        # Real Part only
        self.u_k = np.zeros((1, n_inout), dtype=int)
        self.y_out_k = np.zeros((1, n_inout), dtype=int)

    def set_unit(self, name: str, value: np.ndarray):
        setattr(self, name, value)

    def get_unit(self, name: str, value: np.ndarray):
        getattr(self, name, value)


class InternalStorage:
    # FF within the Unit
    def __init__(self, n_inout: int = 4, n_hidden: int = 8):
        self.n_inout = n_inout
        self.n_hidden = n_hidden

        self.x_state = Complex_Num(np.zeros((1, n_hidden)), np.zeros((1, n_hidden)))
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
    x_array = Complex_Num(np.zeros((1, n_hidden)),
                          np.zeros((1, n_hidden)))

    # input vector
    u_k = np.zeros((1, n_inout))


    x_i_k = Complex_Num(0, 0)
    y_i_k = Complex_Num(0, 0)

    # ------------------------------------------------------
    # [1] Update internal state x_k
    # ------------------------------------------------------
    for i in range(n_hidden):

        # ---------- Real Part -----------
        # Lambda * x_i[k-1] => R*R - C*C for complex numbers
        x_i_k.R += x_array.R[i] * DS.lambda_v.R[i]
        x_i_k.R += - x_array.C[i] * DS.lambda_v.C[i]

        # Loop over B items
        for j in range(n_inout):
            x_i_k.R += DS.B_matrix.R[i, j] * u_k[j]

        # Add b bias
        x_i_k.R += DS.b_bias.R[i]


        # ---------- Complex Part -----------
        # Lambda * x_i[k-1] => R*C + C*R for complex numbers
        x_i_k.C += x_array.R[i] * DS.lambda_v.C[i]
        x_i_k.C += x_array.C[i] * DS.lambda_v.R[i]

        # Loop over B items
        for j in range(n_inout):
            x_i_k.C += DS.B_matrix.C[i, j] * u_k[j]

        # Add b bias
        x_i_k.C += DS.b_bias.C[i]

    # ------------------------------------------------------
    # Compute output y_k
    # ------------------------------------------------------
    for i in range(n_inout):

        # ---------- Real Part -----------
        # Loop over C items
        for j in range(n_hidden):
            y_i_k.R += DS.C_matrix.R[i, j] * x_i_k.R[i]
            y_i_k.R += - DS.C_matrix.C[i, j] * x_i_k.C[i]

        # Add b bias
        y_i_k.R += DS.c_bias.R[i]

        # ReLU + Skip layer
        y_i_k.R = u_k[i] + y_i_k.R if y_i_k.R > 0 else 0

    return x_i_k, y_i_k


def show_IS(IS: InternalStorage):
    print(f"\nCurrent X-state [len={IS.n_hidden}]:")
    print(f"REAL: {[IS.x_state.R[0, i] for i in range(IS.n_hidden)]}")
    print(f"COMP: {[IS.x_state.C[0, i] for i in range(IS.n_hidden)]}")

    print(f"\nInput u_k [len={IS.n_inout}]:")

    print(f"\nacc:")
    print(f"REAL: {[IS.acc]}")

    print(f"\nx_int:")
    print(f"REAL: {[IS.x_int.R]}")
    print(f"COMP: {[IS.x_int.C]}")


def fill_with_random_inputs(IS: InternalStorage, DS: DataStream):

    # Weight values
    DS.lambda_v = Complex_Num(np.random.randint(size=(1, n_hidden), low=0, high=3),
                              np.random.randint(size=(1, n_hidden), low=0, high=3))
    DS.B_matrix = Complex_Num(np.random.randint(size=(n_hidden, n_inout), low=0, high=3),
                              np.random.randint(size=(n_hidden, n_inout), low=0, high=3))
    DS.C_matrix = Complex_Num(np.random.randint(size=(n_inout, n_hidden), low=0, high=3),
                              np.random.randint(size=(n_inout, n_hidden), low=0, high=3))
    DS.b_bias = Complex_Num(np.random.randint(size=(1, n_hidden), low=0, high=3),
                            np.random.randint(size=(1, n_hidden), low=0, high=3))
    DS.c_bias = Complex_Num(np.random.randint(size=(1, n_inout), low=0, high=3),
                            np.random.randint(size=(1, n_inout), low=0, high=3))
    DS.u_k = np.random.randint(size=(1, n_inout), low=0, high=3)
    DS.y_out_k = np.zeros((1, n_inout))

    # Register Values
    IS.x_state = Complex_Num(np.zeros((1, n_hidden)),
                             np.zeros((1, n_hidden)))
    IS.acc = np.zeros(1)
    IS.x_int = Complex_Num(np.zeros(1), np.zeros(1))


def sequence(IS: InternalStorage, DS: DataStream):
    # UPDATE HIDDEN STATE X_K
    for i in range(n_hidden):
        # REAL PART
        IS.x_int.R = fma(mul1=DS.lambda_v.R[0, i],
                         mul2=IS.x_state.R[0, i],
                         add=DS.b_bias.R[0, i])
        IS.x_int.R = fma(mul1=DS.lambda_v.C[0, i],
                         mul2=IS.x_state.C[0, i],
                         add=IS.x_int.R)

        for j in range(n_inout):
            IS.x_int.R = fma(mul1=DS.B_matrix.R[i, j],
                             mul2=DS.u_k[0, j],
                             add=IS.x_int.R)

        # COMPLEX PART
        IS.x_int.C = fma(mul1=DS.lambda_v.R[0, i],
                         mul2=IS.x_state.C[0, i],
                         add=DS.b_bias.C[0, i])
        IS.x_int.C = fma(mul1=DS.lambda_v.C[0, i],
                         mul2=IS.x_state.R[0, i],
                         add=IS.x_int.C)

        for j in range(n_inout):
            IS.x_int.C = fma(mul1=DS.B_matrix.C[i, j],
                             mul2=DS.u_k[0, j],
                             add=IS.x_int.C)

        # Copy intermediate states into SRAM
        IS.x_state.R[0, i] = IS.x_int.R
        IS.x_state.C[0, i] = IS.x_int.C

    # CALCULATE Y_K0
    for j in range(n_inout):
        for i in range(n_hidden):
            IS.acc = fma(mul1=DS.C_matrix.R[j, i],
                         mul2=IS.x_state.R[0, i],
                         add=DS.c_bias.R[0, j])
            IS.acc = fma(mul1=DS.C_matrix.C[j, i],
                         mul2=IS.x_state.C[0, i],
                         add=IS.acc)

        # SKIP-LAYER & ReLU
        DS.y_out_k[0, j] = fma(mul1=IS.acc,
                               mul2=0 if IS.acc < 0 else 1,
                               add=DS.u_k[0, j])
    return IS, DS


def gen_datastream(DS: DataStream):

    s = []

    for i in range(n_hidden):
        # REAL PART
        s.append([DS.lambda_v.R[0, i],
                  DS.b_bias.R[0, i]])
        s.append([DS.lambda_v.C[0, i],
                  "XXXXXXXX"])

        for j in range(n_inout):
            s.append([DS.B_matrix.R[i, j],
                      DS.u_k[0, j]])

        s.append([DS.lambda_v.R[0, i],
                  DS.b_bias.R[0, i]])
        s.append([DS.lambda_v.C[0, i],
                  "XXXXXXXX"])

        for j in range(n_inout):
            s.append([DS.B_matrix.C[i, j],
                      DS.u_k[0, j]])

        s.append(["XXXXXXXX",
                  "XXXXXXXX"])
        s.append(["XXXXXXXX",
                  "XXXXXXXX"])

    # CALCULATE Y_K0
    for j in range(n_inout):
        for i in range(n_hidden):

            s.append([DS.C_matrix.R[j, i],
                      DS.c_bias.R[0, j]])
            s.append([DS.C_matrix.C[j, i],
                      "XXXXXXXX"])

        s.append(["XXXXXXXX",
                  DS.u_k[0, j]])

    # Fixate bitstream
    s_new = []

    for k, str in enumerate(s):
        s1, s2 = str

        if s1 == "XXXXXXXX":
            s1 = bin(0).replace("0b", "").zfill(8)
        else:
            s1 = bin(s1).replace("0b", "").zfill(8)

        if s2 == "XXXXXXXX":
            s2 = bin(0).replace("0b", "").zfill(8)
        else:
            s2 = bin(s2).replace("0b", "").zfill(8)
        s_new.append(s1 + s2)

    return s_new


def math_groundtruth(IS: InternalStorage, DS: DataStream):

    # Inputs:
    u_k = DS.u_k.T
    x_k = IS.x_state.R + IS.x_state.C * 1.0j

    # Weights:
    lambda_v = DS.lambda_v.R + DS.lambda_v.C * 1.0j
    B = DS.B_matrix.R + DS.B_matrix.C * 1.0j
    b = DS.b_bias.R + DS.b_bias.C * 1.0j
    C = DS.C_matrix.R + DS.C_matrix.C * 1.0j
    c = DS.c_bias.R + DS.c_bias.C * 1.0j

    x_k_new = lambda_v.T * x_k.T + (B @ u_k) + b.T
    y_k_out = (C @ x_k_new) + c.T
    y_k_out_R = np.real(y_k_out)

    mask = np.where(y_k_out_R < 0)
    y_k_out_R[mask] = 0
    y_out = u_k + y_k_out_R

    return x_k_new, y_out

if __name__ == "__main__":

    n_inout = 4
    n_hidden = 8

    # Create and init memory
    DS = DataStream(n_inout=n_inout, n_hidden=n_hidden)
    IS = InternalStorage(n_inout=n_inout, n_hidden=n_hidden)
    fill_with_random_inputs(IS, DS)

    s = gen_datastream(DS)
    with open("uint8_tb.txt", "w") as f:
        for line in s:
            f.write(line + "\n")

    IS, DS = sequence(IS, DS)
    x_new = IS.x_state
    y_out = DS.y_out_k

    with open("uint8_tb_test_vec", "w") as g:
        vec = "".join([str(y_out.T[k])[1] + ", " for k in range(n_inout)])
        g.write(vec)


    print(f"X_s: {x_new.R + x_new.C * 1.0j}")
    print(f"Y_s: {y_out}")
