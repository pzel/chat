.PHONY: start-chat kill-chat test

test: chat start-chat
	./test.escript

chat: chat.pony
	ponyc -d

start-chat:
	./chat &

kill-chat:
	-pkill -f chat
