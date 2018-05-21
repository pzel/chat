# chat

You need Pony and Erlang to run the server and e2e tests, respectively.
Run `make` to trigger the process.

# ”Usage”

The server runs locally on port 9999. Any new TCP client gets asked to submit their
nickname. Afterwards, anything this client sends on the wire will be broadcast to all
other clients.

# TODO:

 [X] sending non-ascii text
 [ ] getting a list of users
 [ ] internal: clean up tags to dead sockets
 [ ] internal: wrap user connection with a dedicated actor
 [ ] chat history
 [ ] one-to-one chat
