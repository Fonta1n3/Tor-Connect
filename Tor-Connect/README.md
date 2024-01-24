#  Tor-Connect

Tor-Connect is a simple app with which runs the latest stable release of Tor.
The point of Tor-Connect is to make running Tor on your Mac and creating/managing 
hidden services for Bitcoin Core easy for anyone.

## Anonymity and Security
This app and as far as I know its libraries (Tor.Framework) and its dependencies 
have not been properly audited, no guarantees thats it is safe to use!

## Features
- Creates hidden services for Bitcoin Core mainnet, testnet, signet and regtest default rpcports.
- Allows you to add `authorized_clients` utilizing Tor V3 authentication.
- Embeds Tor.
- Automatically starts Tor and configures your hidden services when you launch the app.
- Quitting the app quits the Tor process and your hidden services will not be reachable.

## TODO
- More fine grained controls for advanced users (run a relay?).
- Full custom torrc into a UI.
- Fine grained control over hidden services.
- Show live log.

