# chat

You need Pony and Erlang to run the server and e2e tests, respectively.
Run `make` to trigger the process.

# ”Usage”

The server runs locally on port 9999. Any new TCP client gets asked to submit their
nickname. Afterwards, anything this client sends on the wire will be broadcast to all
other clients.

# TODO:

 - [x] sending non-ascii text
 - [x] rejecting duplicate user names
 - [ ] getting a list of users
 - [x] internal: clean up tags to dead sockets
 - [x] internal: wrap user connection with a dedicated actor
 - [ ] chat history
 - [ ] one-to-one chat
