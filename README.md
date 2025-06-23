# Web3 Pi Archive OS

**Web3 Pi Archive OS** is a custom Ubuntu-based image built specifically for running a Ethereum Archive Node on x86.

This project is a fork of the [Armbian Build Framework](https://github.com/armbian/build), extended with preinstalled packages, configurations, and system tweaks tailored for Web3 Pi.


---

### 🚧 Status

This project is currently in its very early development phase and **not yet ready for production or public use**. Expect frequent changes and incomplete features.

---

### 🛠 Build Instructions

> 🐳 **Docker is required** to build the image.

Clone the repository and start the build:

```sh
git clone --branch=w3p-staking-os https://github.com/Web3-Pi/web3-pi-staking-os.git
cd build
./compile.sh w3p
```

---

### License

This software is published under the GPL-2.0 License license.
