import numpy as np
from chain import options_chain


def main():
    # define inputs
    K = 210
    T = 0.25
    r = 0.05
    sigma = 0.30
    S_range = np.linspace(150, 250, 100)

    df = options_chain(S_range, K, T, r, sigma)

    print(df.to_string())


if __name__ == "__main__":
    main()
