#!/usr/bin/env escript
%% This is an end-to-end test for the chat server.
%% It's in Erlang because I don't know any better.
-define(fail(F), begin io:format("~p:~p~n", [?LINE,F]), erlang:halt(1) end).
-define(assert(Exp), case (catch Exp) of ok -> ok; _ -> ?fail(Exp) end).

main(_) ->
    ?assert(single_process_can_connect()),
    ?assert(multiple_processes_can_connect()),
    ?assert(a_new_connection_is_asked_for_nickname()),
    ?assert(a_new_connection_gets_list_of_users()),
    ?assert(a_new_connection_gets_kicked_if_nickname_is_taken()),
    ?assert(a_new_connection_can_broadcast_chats()),
    ?assert(users_dont_receive_their_own_messages()),
    ?assert(all_other_connections_will_receive_chats()),
    io:format("~ts~n", ["All tests passed"]),
    erlang:halt(0).

single_process_can_connect() ->
    {ok, P} = connect(),
    ok = gen_tcp:close(P).

multiple_processes_can_connect() ->
    Parent = self(),
    Connect = fun() ->
                      {ok, P} = connect(),
                      Parent ! ok,
                      ok = gen_tcp:close(P)
              end,
  [ spawn(Connect) || _I <- lists:seq(1,100) ],
  ok = receive_oks(100).

a_new_connection_is_asked_for_nickname() ->
    {ok, P} = connect(),
    {ok, "Input your nickname: "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, "User1\n"),
    {ok, "Welcome, User1.\n"} = gen_tcp:recv(P,0,1000),
    gen_tcp:close(P),
    ok.

a_new_connection_gets_list_of_users() ->
    {ok, Peach} = connect(),
    ok = set_nickname(Peach, "Peach"),
    {ok, "[Users: [Peach]]" ++ _} = gen_tcp:recv(Peach,0,1000),

    {ok, Daisy} = connect(),
    ok = set_nickname(Daisy, "Daisy"),
    {ok, "[Users: [Daisy,Peach]]" ++ _} = gen_tcp:recv(Daisy,0,1000),

    gen_tcp:close(Peach),
    gen_tcp:close(Daisy),
    ok.

connect() -> connect([{active, false}]).
connect(Opts) -> gen_tcp:connect("localhost", 9999, Opts).

a_new_connection_gets_kicked_if_nickname_is_taken() ->
    {ok, P1} = connect(),
    ok = set_nickname(P1, "Mario"),

    {ok, P2} = connect(),
    {ok, "Input your nickname: "} = gen_tcp:recv(P2,0,1000),
    ok = gen_tcp:send(P2, "Mario\n"),
    {ok, "[ERROR: Username Mario already taken]\n"} = gen_tcp:recv(P2,0,1000),
    {error, closed} = gen_tcp:recv(P2,0,1000),
    ok.

a_new_connection_can_broadcast_chats() ->
    {ok, P} = connect(),
    ok = set_nickname(P, "Food"),
    ok = receive_userlist(P),
    ok = type_message(P, "hello everyone"),
    ok.

users_dont_receive_their_own_messages() ->
    % given
    {ok, P} = connect(),
    ok = set_nickname(P, "Toad"),
    ok = receive_userlist(P),

    % when
    ok = type_message(P, "hello everyone"),
    ok = inet:setopts(P, [{active, true}]),

    % then
    ok = receive {tcp,_, "> "} -> ok after 50 -> ?fail(no_prompt) end,
    nothing_arrived = receive A -> A after 50 -> nothing_arrived end,
    ok.

all_other_connections_will_receive_chats() ->
    {ok, UserASocket} = connect(),
    ok = set_nickname(UserASocket, "UserA"),
    ok = receive_userlist(UserASocket),

    Parent = self(),
    Connect = fun(I) ->
                      {ok, P} = connect(),
                      ok = set_nickname(P, "AUser"++integer_to_list(I)),
                      ok = receive_userlist(P),
                      {ok, "> "} = gen_tcp:recv(P, 0, 1000),
                      Parent ! ok, % all connected
                      ok = inet:setopts(P, [{active, true}, binary]),
                      receive
                          {tcp, _, <<"[UserA]: 文章jaźń\n> "/utf8>>} -> Parent ! ok;
                          {tcp, _, Other} -> ?fail({unexpected_tcp, Other})
                          after 1000 -> ?fail({I, didnt_get_message})
                      end,
                      ok = gen_tcp:close(P)
              end,
    [ spawn(fun() -> Connect(I) end) || I <- lists:seq(1,100) ],
    ok = receive_oks(100),
    ok = type_message(UserASocket, <<"文章jaźń"/utf8>>),
    ok = receive_oks(100).

set_nickname(P, Nick) when is_list(Nick) ->
    {ok, "Input your nickname: "} = gen_tcp:recv(P,0,1000),
    ok = gen_tcp:send(P, Nick),
    {ok, "Welcome" ++_ } = gen_tcp:recv(P,0,1000),
    ok.

receive_userlist(P) ->
    {ok, "[Users: " ++ _ } = gen_tcp:recv(P, 0, 1000),
    gen_tcp:send(P, "\n"),
    ok.

type_message(P, Message) when is_list(Message); is_binary(Message) ->
    case gen_tcp:recv(P,0,1000) of
        {ok, "> "} -> ok;
        Other -> ?fail({got, Other, when_sending, Message})
    end,
    ok = gen_tcp:send(P, [Message, "\n"]).

receive_oks(0) -> ok;
receive_oks(N) ->
    receive  ok -> receive_oks(N-1)
    after 100 -> ?fail(not_enough_oks)
    end.
