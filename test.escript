#!/usr/bin/env escript
% This is an end-to-end test for the chat server.
% It's in Erlang because I don't know any better.

main(_) ->
    ok = single_process_can_connect(),
    ok = multiple_processes_can_connect(),
    ok = a_new_connection_is_asked_for_nickname(),
    ok = a_new_connection_can_broadcast_chats(),
    ok = all_other_connections_will_receive_chats(),
    io:format("~ts~n", ["All tests passed"]),
    erlang:halt(0).

single_process_can_connect() ->
    {ok, P} = gen_tcp:connect("localhost", 9999, []),
    ok = gen_tcp:close(P).

multiple_processes_can_connect() ->
    Parent = self(),
    Connect = fun() ->
                      {ok, P} = gen_tcp:connect("localhost", 9999, []),
                      Parent ! ok,
                      ok = gen_tcp:close(P)
              end,
  [ spawn(Connect) || _I <- lists:seq(1,100) ],
  ok = receive_oks(100).

a_new_connection_is_asked_for_nickname() ->
    {ok, P} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    {ok, "Input your nickname: "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, "User1\n"),
    {ok, "Welcome, User1.\n"} = gen_tcp:recv(P,0,1000),
    {ok, "> "} = gen_tcp:recv(P,0,1000),
    ok.

a_new_connection_can_broadcast_chats() ->
    {ok, P} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    ok = set_nickname(P, "Mario"),
    ok = type_message(P, "hello everyone").


all_other_connections_will_receive_chats() ->
    {ok, UserASocket} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    ok = set_nickname(UserASocket, "UserA"),

    Parent = self(),
    Connect = fun(I) ->
                      {ok, P} = gen_tcp:connect("localhost", 9999, [{active, false}]),
                      ok = set_nickname(P, "User"++integer_to_list(I)),
                      ok = inet:setopts(P, [{active, true}]),
                      receive
                          {tcp, _, "> [UserA]: aaa\n> "} -> Parent ! ok
                          after 1000 -> erlang:display({I, didnt_get_message})
                      end,
                      ok = gen_tcp:close(P)
              end,
    [ spawn(fun() -> Connect(I) end) || I <- lists:seq(1,100) ],
    ok = type_message(UserASocket, "aaa"),
    ok = receive_oks(100).


set_nickname(P, Nick) when is_list(Nick) ->
    {ok, "Input your nickname: "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, Nick),
    {ok, "Welcome" ++_ } = gen_tcp:recv(P,0,1000),
    ok.

type_message(P, Message) when is_list(Message) ->
    {ok, "> "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, Message ++ "\n"),
    ok.


receive_oks(0) -> ok;
receive_oks(N) ->
    receive  ok -> receive_oks(N-1)
    after 100 -> error(not_enough_oks)
    end.
