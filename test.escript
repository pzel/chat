#!/usr/bin/env escript
%% This is an end-to-end test for the chat server.
%% It's in Erlang because I don't know any better.
-define(fail(F), begin io:format("~p~n", [F]), erlang:halt(1) end).

main(_) ->
    ok = single_process_can_connect(),
    ok = multiple_processes_can_connect(),
    ok = a_new_connection_is_asked_for_nickname(),
    ok = a_new_connection_gets_kicked_if_nickname_is_taken(),
    % ok = a_new_connection_gets_list_of_users(),
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

a_new_connection_gets_kicked_if_nickname_is_taken() ->
    {ok, P1} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    ok = set_nickname(P1, "Mario"),

    {ok, P2} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    {ok, "Input your nickname: "} = gen_tcp:recv(P2,0,1000),
    ok = gen_tcp:send(P2, "Mario\n"),
    {ok, "[ERROR: Username already taken]\n"} = gen_tcp:recv(P2,0,1000),
    {error, closed} = gen_tcp:recv(P2,0,1000),
    ok.

%% a_new_connection_gets_list_of_users() ->
%%     {ok, Foo} = gen_tcp:connect("localhost", 9999, [{active, false}]),
%%     {ok, "Input your nickname: "} = gen_tcp:recv(Foo,0,1000),
%%     ok = gen_tcp:send(Foo, "Foo\n"),
%%     {ok, "Welcome, Foo.\n"} = gen_tcp:recv(Foo,0,1000),
%%     {ok, "[Users in room: ]\n> \n"} = gen_tcp:recv(Foo,0,1000),

%%     {ok, Bar} = gen_tcp:connect("localhost", 9999, [{active, false}]),
%%     {ok, "Input your nickname: "} = gen_tcp:recv(Bar,0,1000),
%%     ok = gen_tcp:send(Bar, "Bar\n"),
%%     {ok, "Welcome, Bar.\n"} = gen_tcp:recv(Bar,0,1000),

%%     ok.

a_new_connection_can_broadcast_chats() ->
    {ok, P} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    ok = set_nickname(P, "Luigi"),
    ok = type_message(P, "hello everyone").

all_other_connections_will_receive_chats() ->
    {ok, UserASocket} = gen_tcp:connect("localhost", 9999, [{active, false}]),
    ok = set_nickname(UserASocket, "UserA"),

    Parent = self(),
    Connect = fun(I) ->
                      {ok, P} = gen_tcp:connect("localhost", 9999, [{active, false}]),
                      ok = set_nickname(P, "AUser"++integer_to_list(I)),
                      ok = inet:setopts(P, [{active, true}, binary]),
                      receive
                          {tcp, _, <<"> [UserA]: 文章jaźń\n> "/utf8>>} -> Parent ! ok;
                          {tcp, _, Other} -> ?fail(Other)
                          after 1000 -> ?fail({I, didnt_get_message})
                      end,
                      ok = gen_tcp:close(P)
              end,
    [ spawn(fun() -> Connect(I) end) || I <- lists:seq(1,100) ],
    ok = type_message(UserASocket, <<"文章jaźń"/utf8>>),
    ok = receive_oks(100).


set_nickname(P, Nick) when is_list(Nick) ->
    {ok, "Input your nickname: "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, Nick),
    {ok, "Welcome" ++_ } = gen_tcp:recv(P,0,1000),
    ok.

type_message(P, Message) when is_list(Message); is_binary(Message) ->
    {ok, "> "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, [Message, "\n"]).

receive_oks(0) -> ok;
receive_oks(N) ->
    receive  ok -> receive_oks(N-1)
    after 100 -> ?fail(not_enough_oks)
    end.
