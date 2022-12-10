from brownie import WBTStrategy


def main():
    source = WBTStrategy.get_verification_info()["flattened_source"]

    with open("flat.sol", "w") as f:
        f.write(source)
