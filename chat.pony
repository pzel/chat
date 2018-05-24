use "collections"
use "debug"
use "net"

class ChatMessage is Stringable
  let text : String
  let from : String

	new create(from': String, text' : String val) =>
    text = text'.clone().>strip()
    from = from'

  fun string() : String iso^ =>
    String.join(["[" ; from ; "]: " ; text ].values())

class ChatConnectionNotify is TCPConnectionNotify
  let _router : Router tag
  var _chat_session : (ChatSession tag | None) = None
  var _tcp_conn : (TCPConnection ref | None) = None

  new iso create(r: Router tag) =>
    _router = r

  fun ref received(conn: TCPConnection ref,
		   data: Array[U8] iso,
		   times: USize) : Bool =>
    let user_input = String.from_array(consume data)
    match (_chat_session, _tcp_conn)
      | (None, let c: TCPConnection ref) =>
          var session = ChatSession(_router, c)
          _chat_session = session
          session.process_user_input(user_input)
      | (let session: ChatSession tag, _) =>
          session.process_user_input(user_input)
      end
    true

  fun ref accepted(conn: TCPConnection ref) =>
    _tcp_conn = conn
    conn.write("Input your nickname: ")

  fun ref closed(conn: TCPConnection ref) =>
    with_chat_session({(session) =>
      session.connection_closed()
    })

  fun ref connect_failed(conn: TCPConnection ref) =>
    None

  fun with_chat_session(fn : {(ChatSession tag)}) : None =>
    match _chat_session
      | None => None
      | let session : ChatSession tag => fn(session)
    end

actor ChatSession
  let _router : Router tag
  let _tcp_conn : TCPConnection tag
  let _prompt : String = "> "
  var _user_name : (String | None) = None

  new create(router: Router tag, connection: TCPConnection tag) =>
    _router = router
    _tcp_conn = connection

  be process_user_input(user_input: String val) =>
    match _user_name
      | None =>
        let name = set_username(user_input)
        register_with_router(name)
        _tcp_conn.write("Welcome, " + name + ".\n")
        _tcp_conn.write(_prompt)
      | let name : String =>
        _tcp_conn.write(_prompt)
        _router.route(recover val ChatMessage(name, user_input) end)
    end

  be connection_closed() =>
    with_user_name({(n) => _router.unregister(n) })

  fun ref set_username(user_input: String val) : String val =>
    let stripped' = recover val user_input.clone().>strip() end
    _user_name = stripped'
    stripped'

  fun ref register_with_router(name: String) =>
    _router.register(name,
      recover val
        this~display_message_received(_tcp_conn, _prompt, _user_name)
      end)

  fun tag display_message_received(
    conn: TCPConnection tag,
    prompt: String val,
    user_name: (String | None),
    msg: ChatMessage val) : None =>
      match (user_name, msg.from)
        | (let s : String, let s': String) if s != s' =>
          conn.write(msg.string())
          conn.write("\n")
          conn.write(prompt)
      else
        // This is our own message
      None
    end

    fun with_user_name(fn : {(String val)}): None =>
      match _user_name
        | (let n: String) => fn(n)
        | None => None
      end

actor Router
  let _env : Env
  var _notifiers : Map[String val, {(ChatMessage val)} val ]

  new create(env: Env) =>
    _env = env
    _notifiers = Map[String val, {(ChatMessage val)} val ].create(10)

  be route(msg: ChatMessage val) =>
    for fn in _notifiers.values() do
      fn(msg)
    end
    _env.out.print(" ".join(
      [msg.string() ; " was sent to"
      _notifiers.size().string(); "users."
      ].values()))

  be register(user_name: String, fn : {(ChatMessage val)} val) =>
    _notifiers.update(user_name, fn)

  be unregister(user_name: String) =>
    try _notifiers.remove(user_name)? end
    None

class ChatTCPListenNotify is TCPListenNotify
  let _env: Env val
  let _router: Router tag


  new create(env: Env val, r : Router tag) =>
    _env = env
    _router = r

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    ChatConnectionNotify(_router)

  fun ref not_listening(listen: TCPListener ref) =>
    _env.out.print("NOT LISTENING")
    None

actor Main
  new create(env: Env) =>
    let router = Router(env)
    try
      TCPListener(env.root as AmbientAuth,
        recover ChatTCPListenNotify(env, router) end, "", "9999")
    end
