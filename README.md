# shi-chain
a Xray relay chaining auto installer 

## Usage
```bash
bash <(curl -sL https://raw.githubusercontent.com/shinya-dono/shiChain/main/installer.sh)
```

then simply choose your relay server and wait for the installation to finish.


## Features
- [x] configures Xray relay
- [x] configures Xray outbound
- [x] installs Namizun 
- [x] install bbr
- [x] fix asiatech bad repos

## Advanced Configuration

you can set these env variables to change the default behavior of the installer
```bash

export INSTALL_PATH= #where to install shiChain (default: /etc/shichain)
export XRAY_PATH= #where to install Xray (default: $INSTALL_PATH/xray)
export CONFIG_PATH= #where to store Xray config (default: $INSTALL_PATH/config.json)
export IRAN_DAT_FILE= #where to store Iran.dat (default: $INSTALL_PATH/iran.dat)
export LOG_PATH= #where to store Xray logs (/var/log/shichain/(access|error).log)
export INSTALL_USER= #user to run Xray (default: nobody)

```

## TODO
- [ ] add more relay options
- [ ] add more outbound options
- [ ] add cloudflare warp support
- [ ] add trojan support
- [ ] add cloudflare masking support

## Credits
- [XTLS](https://github.com/XTLS)
- [Namizun](https://github.com/malkemit/namizun)

## License
[MIT](https://choosealicense.com/licenses/mit/)

## Donate
### USDT TRC20
```
TD5Mh9e38EDeQRFUunBRTeb5UXYLobt9rj
```
