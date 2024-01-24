#  Tor-Connect Alpha

Tor-Connect is a simple app with which runs the latest stable release of Tor.
The point of Tor-Connect is to make running Tor on your Mac and creating/managing 
hidden services for Bitcoin Core easy for anyone. 

## How to use it?
- `git clone https://github.com/Fonta1n3/Tor-Connect`
- `cd Tor-Connect`
- Double click the Tor-Connect.xcworkspace to launch the app with Xcode.
- It should "just work".

## Dependencies
[Tor.Framework](https://github.com/iCepa/Tor.framework) is the only dependency.

## Anonymity and Security
This app and as far as I know its frameworks (Tor.Framework) and their dependencies 
have not been properly audited, no guarantees that it is safe, private or anonymous to use!

## Features
- Creates hidden services for Bitcoin Core mainnet, testnet, signet and regtest default rpcports.
- Allows you to add `authorized_clients` utilizing Tor V3 authentication.
- Embeds Tor.
- Automatically starts Tor and configures your hidden services when you launch the app.
- Quitting the app quits the Tor process and your hidden services will not be reachable.

## TODO
- App Store release.
- More fine grained controls for advanced users (run a relay?).
- Full custom torrc into a UI.
- Fine grained control over hidden services.
- Show live log.

