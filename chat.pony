use "collections"
use "debug"
use "net"

class ChatMessage is Stringable
  let text : String
  let from : String
  new create(from': String, text' : String val) =>
    text = text'.clone()
    // TODO: Strip newlines from the end
    // without mangling utf8
    from = from'

  fun string() : String iso^ =>
    String.join(["[" ; from ; "]: " ; text ].values())

class ChatConnectionNotify is TCPConnectionNotify
  let _prompt : String = "> "
  let _router : Router tag
  var _user_name : (String | None) = None
  var _tcp_conn : (TCPConnection ref | None) = None

  new iso create(r: Router tag) =>
    _router = r

  fun ref received(
    conn: TCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool =>
    let user_input = String.from_array(consume data)
    match _user_name
      | None =>
        let name = set_username(user_input)
        register_with_router()
        conn.write("Welcome, " + name + ".\n")
      | let name : String =>
        _router.route(recover val ChatMessage(name, user_input) end)
    end
    conn.write(_prompt)
    true

  fun ref set_username(user_input: String val) : String val =>
    let stripped' = recover val user_input.clone().>strip() end
    _user_name = stripped'
    stripped'

  fun ref register_with_router() =>
    match _tcp_conn
      | None => None
      | let x : TCPConnection =>
          _router.register(recover val
            this~display_message_received(x, _prompt, _user_name)
          end)
      end

  fun tag display_message_received(
    conn: TCPConnection tag,
    prompt: String val,
    user_name: (String | None),
    msg: ChatMessage val) : None =>
      match (user_name, msg.from)
        | (let s : String, let s': String) if s != s' =>
          conn.write(msg.string())
          conn.write(prompt)
      else
        // This is our own message
        None
      end

  fun ref accepted(conn: TCPConnection ref) =>
    _tcp_conn = conn
    conn.write("Input your nickname: ")

  fun ref connect_failed(conn: TCPConnection ref) => None

actor Router
  let _env : Env
  var _notifiers : Array[ {(ChatMessage val)} val ]

  new create(env: Env) =>
    _env = env
    _notifiers = []

  be route(msg: ChatMessage val) =>
    for fn in _notifiers.values() do
      fn(msg)
    end
    _env.out.print(" ".join(
      [msg.string() ; " was sent to" ; _notifiers.size().string(); "users."
      ].values()))

  be register(fn : {(ChatMessage val)} val) =>
    _notifiers.push(fn)


class ChatTCPListenNotify is TCPListenNotify
  let _router : Router tag

  new create(r : Router tag) =>
    _router = r

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    ChatConnectionNotify(_router)

  fun ref not_listening(listen: TCPListener ref) =>
    None

actor Main
  new create(env: Env) =>
    let router = Router(env)
    try
      TCPListener(env.root as AmbientAuth,
        recover ChatTCPListenNotify(router) end, "", "9999")
    end
