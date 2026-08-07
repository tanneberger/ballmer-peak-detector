import softfloatpy as sp

def encode_to_posit(a: float):
    posit = sp.posit16(a)
    print(posit)

if __name__ == '__main__':
    encode_to_posit(10)