use "collections"
use "itertools"
use "debug"
use "net"
use "promises"


class ChatMessage is Stringable
  let text : String
  let from : String

	new val create(from': String, text' : String val) =>
    text = text'.clone().>strip()
    from = from'

  fun string() : String iso^ =>
    String.join(["[" ; from ; "]: " ; text ].values())

type RegistrationResult is (UsernameTaken val | SuccessfulRegistration val)

class UsernameTaken
  let name: String
  new val create(name': String val) =>
    name = name'

class SuccessfulRegistration
  let name: String
  let user_list: Array[String] val
  new val create(name': String, user_list': Array[String] val) =>
    name = name'
    user_list = user_list'

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

class ChatConnectionNotify is TCPConnectionNotify
  let _router : Router tag
  var _chat_session : (ChatSession tag | None) = None
  var _tcp_conn : (TCPConnection ref | None) = None

  new iso create(r: Router tag) =>
    _router = r

  fun ref accepted(conn: TCPConnection ref) =>
    _tcp_conn = conn
    _chat_session = ChatSession(_router, conn)

  fun ref closed(conn: TCPConnection ref) =>
    match _chat_session
      | None => None
      | let session : ChatSession tag => session.connection_closed()
    end

  fun ref connect_failed(conn: TCPConnection ref) =>
    None

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

actor ChatSession
  let _router : Router tag
  let _tcp_conn : TCPConnection tag
  let _prompt : String = "> "
  var _user_name : (String | None) = None
  var _registration_pending : Bool = false

  new create(router: Router tag, conn: TCPConnection tag) =>
    _router = router
    _tcp_conn = conn
    ask_for_username()

  be ask_for_username() =>
    _tcp_conn.write("Input your nickname: ")

  be process_user_input(user_input: String val) =>
    match (_user_name, _registration_pending)
      | (None, false) =>
        _registration_pending = true
        register_with_router(user_input.clone().>strip())
      | (let name : String, false) =>
        _tcp_conn.write(_prompt)
        _router.route(ChatMessage(name, user_input))
      | (_, true) =>
        // This represents a race condition.
        // The username hasn't yet been registered, but we're already
        // getting data from the user.
        // Should we queue up the messages that arrive,
        // or signal an error and drop the connection?
        /// Ingoring the messages is the worst of both worlds :)
        None
    end

  be connection_closed() =>
    with_user_name({(n) => _router.unregister(n) })

  be username_taken(name: String) =>
    _tcp_conn.write("[ERROR: Username already taken]\n")
    _tcp_conn.dispose()

  be welcome_user(name: String, user_list: Array[String] val) =>
    _user_name = name
    _registration_pending = false
    _tcp_conn.write("Welcome, " + name + ".\n")
    _tcp_conn.write(_prompt)

  be handle_routed_message(msg: ChatMessage val) =>
    _tcp_conn.write(msg.string())
    _tcp_conn.write("\n")
    _tcp_conn.write(_prompt)

  fun ref set_username(user_input: String val) : String val =>
    let stripped' = recover val user_input.clone().>strip() end
    _user_name = stripped'
    stripped'

  fun ref register_with_router(name: String) =>
    let on_register = Promise[RegistrationResult val]
    on_register.next[None](recover iso this~handle_register_res(_tcp_conn) end)
    _router.try_register(name, on_register, this)

  fun tag handle_register_res(conn: TCPConnection, res: RegistrationResult) =>
    match res
      | let t: UsernameTaken val => username_taken(t.name)
      | let s: SuccessfulRegistration val => welcome_user(s.name, s.user_list)
    end

  fun with_user_name(fn : {(String val)}): None =>
    match _user_name
      | (let n: String) => fn(n)
      | None => None
    end

actor Router
  let _env : Env
  var _notifiers : Map[String val, ChatSession tag]

  new create(env: Env) =>
    _env = env
    _notifiers = Map[String val, ChatSession tag].create(10)

  fun ref user_list() : Array[String] val =>
    var result : Array[String] iso = recover Array[String] end
    // TODO: Ask ponylang folks why Iter[] (  ).collect(result)
    // doesn't work here.
    for k in _notifiers.keys() do result.push(k) end
    recover val result end

  be route(msg: ChatMessage val) =>
    for (user_name, session) in _notifiers.pairs() do
      if user_name != msg.from then session.handle_routed_message(msg) end
    end
    _env.out.print(" ".join(
      [msg.string() ; " was sent to"
      _notifiers.size().string(); "users."
      ].values()))

  be try_register(name: String,
                  on_register: Promise[RegistrationResult val],
                  session: ChatSession tag) =>
    if _notifiers.contains(name)
      then on_register(UsernameTaken(name))
      else
        _notifiers.update(name, session)
     on_register(SuccessfulRegistration(name, user_list()))
    end

  be unregister(user_name: String) =>
    try _notifiers.remove(user_name)? end
    None

actor Main
  new create(env: Env) =>
    let router = Router(env)
    try
      TCPListener(env.root as AmbientAuth,
        recover ChatTCPListenNotify(env, router) end, "", "9999")
    end
