/**
 * ============================================================================ *
 * @author      RaptorX                                                        *
 * @version     0.0.0                                                          *
  * @devPath     S:\lib\v2\DeepSeek\OpenRouter.ahk                            *
 * @description                                                                *
 * =========================================================================== *
 * Want a clear path for learning AutoHotkey?                                  *
 * Take a look at our AutoHotkey courses here: the-Automator.com/Discover      *
 * They're structured in a way to make learning AHK EASY                       *
 * And come with a 200% moneyback guarantee so you have NOTHING to risk!       *
 * =========================================================================== *
 * @license     CC BY 4.0                                                      *
 * =========================================================================== *
   This work by the-Automator.com is licensed under CC BY 4.0

   Attribution — You must give appropriate credit , provide a link to the license,
   and indicate if changes were made.

   You may do so in any reasonable manner, but not in any way that suggests the licensor
   endorses you or your use.

   No additional restrictions — You may not apply legal terms or technological measures that
   legally restrict others from doing anything the license permits.
 */
class OpenRouter {
	static ModelData := map()
	static api_base := 'https://api.deepseek.com/v1'
	static headers := Map(
		'Authorization', '', ; <DEEPSEEK_API_KEY>
		'Content-Type' , 'application/json',
	)

	static ini := 'UIA_Inspector_settings.ini'
	static authorized => !!this.headers['Authorization']

	/**
	 *
	 * @param {String} api_key
	 * @param {Map} headers custom headers that can be used to update basic headers
	 * @returns {true|false}
	 */
	static Authenticate(api_key, headers := Map()) {
		OutputDebug '--- ' A_ThisFunc ' start ---' '`n'

		OutputDebug 'validating parameters`n'
		if !(api_key is String)
			throw TypeError('expected api_key to be a String', -1, 'got: ' Type(api_key))
		if !(headers is Map)
			throw TypeError('expected headers to be a Map', -1, 'got: ' Type(headers))

		OutputDebug 'setting custom headers`n'
		for key, val in headers {
			if !val || !key || key ~= 'i)Authorization|Content-Type'
			continue
			OpenRouter.headers[key] := val
		}

		OutputDebug 'setting authorization token`n'
		OpenRouter.headers['Authorization'] := Format('Bearer {}', api_key)

		; Validate by making a lightweight models list request
		try {
			http := OpenRouter.Request('GET', 'models')
			res := http.Status = 200
			if !res {
				OutputDebug 'resetting Authorization key`n'
				OpenRouter.headers['Authorization'] := ''
			}
		} catch {
			OpenRouter.headers['Authorization'] := ''
			res := false
		}

		OutputDebug '--- ' A_ThisFunc ' end ---' '`n'
		return res
	}

	/**
	 *
	 * @param {String} method
	 * @param {String} url
	 * @param {Object} body
	 * @param {Map} headers
	 * @param {typeof Func} async
	 *
	 * @returns {typeof OpenRouter.RawResponse | typeof Func}
	 */
	static Request(method, endpoint, headers := Map(), body?, async?) {
		OutputDebug '--- ' A_ThisFunc ' start ---' '`n'
		OutputDebug 'validating parameters`n'
		if !(method is String)
			throw TypeError('expected method to be a String', -1, 'got: ' Type(method))
		if !(endpoint is String)
			throw TypeError('expected url to be a String', -1, 'got: ' Type(endpoint))
		if !(headers is Map)
			throw TypeError('expected headers to be a Map', -1, 'got: ' Type(headers))
		if IsSet(body) && !(body is Object)
			throw TypeError('expected body to be an Object', -1, 'got: ' Type(body))
		if IsSet(async) && !(async is Func)
			throw TypeError('expected async to be a Func', -1, 'got: ' Type(async))

		URL := OpenRouter.api_base '/' endpoint
		http := ComObject('WinHttp.WinHttpRequest.5.1')
		OutputDebug 'starting request to ' URL '`n'
		http.Open(method, URL, true)

		OutputDebug 'setting custom headers`n'
		for header, value in headers {
			if !value {
				OutputDebug 'ignoring ' header ' because of empty value' '`n'
				continue
			}

			OutputDebug 'setting ' header ' to ' value '`n'
			OpenRouter.headers[header] := value
		}

		OutputDebug 'setting headers`n'
		for header, value in OpenRouter.headers {
			if !value {
				OutputDebug 'ignoring ' header ' because of empty value' '`n'
				continue
			}

			OutputDebug 'setting ' header ' to ' value '`n'
			http.SetRequestHeader(header, value)
		}

		http.Send(IsSet(body) ? s:= JSON.Stringify(body) : '')
		OutputDebug '--- ' A_ThisFunc ' end ---' '`n'

		switch IsSet(async) {
		case true:
			SetTimer %async%.Bind(http), 100
			return async
		case false:
			http.WaitForResponse()
			return OpenRouter.Response(http)
		}
	}

	/**
	 * @documentation\
	 * The body/payload object that would be send has some required parameters\
	 * and many optional ones. Here you can find a list of some general parameters\
	 * and some specific to this interface.
	 * 
	 * {@link https://api-docs.deepseek.com/ General Parameters}
	 *
	 * ---
	 * 
	 * #### Methods
	 * ---
	 * 
	 * @method __new constructor
	 */
	class Completions {
		__New(body){
			OutputDebug '--- ' A_ThisFunc ' start ---' '`n'
			OutputDebug 'validating parameters`n'
			if !(body is Object)
				throw TypeError('expected body to be an Object', -1, 'got: ' Type(body))

			for prop in ['model','prompt'] {
				if !body.HasProp(prop)
					throw ValueError('required property missing for completions body', -1, 'missing: ' prop)
			}

			OutputDebug 'validating authorization`n'
			if !OpenRouter.authorized
			{
				OutputDebug 'not authorized, trying to authenticate`n'
				try {
					apiKey := IniRead(A_ScriptDir "\settings.ini", "DeepSeek", "api_key", "")
					if apiKey = ""
						throw Error("No DeepSeek API key configured.")
					if !OpenRouter.Authenticate(apiKey)
						throw Error('could not authenticate with DeepSeek')
				} catch as err {
					throw Error(err.Message)
				}
			}

			OutputDebug 'creating the completions request`n'
			res := OpenRouter.Request('POST', 'completions',, body)
			; OutputDebug 'raw response text: ' res.ResponseText '`n'

			OutputDebug 'parsing the response`n'
			for key, val in JSON.Parse(res.ResponseText)
				this.%key% := val

			this.Base := OpenRouter.Response.Prototype
			OutputDebug '--- ' A_ThisFunc ' end ---' '`n'
		}
	}

	class Chat {
		/**
		 * @documentation\
		 * The body/payload object that would be send has some required parameters\
		 * and many optional ones. Here you can find a list of some general parameters\
		 * and some specific to this interface.
		 * 
		 * {@link https://api-docs.deepseek.com/guides/chat_api DeepSeek Chat Completion API}
		 *
		 * ---
		 * 
		 * #### Methods
		 * ---
		 * 
		 * @method __new constructor
		 */
		class Completions {
			__New(body){
				OutputDebug '--- ' A_ThisFunc ' start ---' '`n'
				OutputDebug 'validating parameters`n'
				if !(body is Object)
					throw TypeError('expected body to be an Object', -1, 'got: ' Type(body))

				for prop in ['model','messages'] {
					if !body.HasProp(prop)
						throw ValueError('required property missing for completions body', -1, 'missing: ' prop)
				}

				if !(body.messages is Array)
					throw TypeError('messages must be a list of message objects', -2, 'got: ' Type(body.messages))

				for message in body.messages {
					for prop in ['role','content'] {
						if !message.HasProp(prop)
							throw ValueError('required property missing for message', -2, 'missing: ' prop)
					}
				}

				OutputDebug 'validating authorization`n'
				if !OpenRouter.authorized
				{
					OutputDebug 'not authorized, trying to authenticate`n'
					try {
						apiKey := IniRead(A_ScriptDir "\settings.ini", "DeepSeek", "api_key", "")
						if apiKey = ""
							throw Error("No DeepSeek API key configured.`n`nOpen Preferences and paste your key into the 'API Key' field.")
						if !OpenRouter.Authenticate(apiKey)
							throw Error('could not authenticate with DeepSeek')
					} catch as err {
						throw Error(err.Message)
					}
				}

				OutputDebug 'creating the completions request`n'
				res := OpenRouter.Request('POST', 'chat/completions',, body)
				; OutputDebug 'raw response text: ' res.ResponseText '`n'

				OutputDebug 'creating the completions request`n'
				OutputDebug 'parsing the response`n'
				for key, val in JSON.Parse(res.ResponseText)
				{
					OutputDebug 'setting property ' key ' to ' val '`n'
					this.%key% := val
				}

				this.Base := OpenRouter.Response.Prototype
				OutputDebug '--- ' A_ThisFunc ' end ---' '`n'
			}

		}

		class Message
		{
			static Create(user, prompt, path := false)
			{
				data := []
				msg := {role:'user',content:[]}
				msg.content.Push(OpenRouter.Chat.Message.addcontent('text', prompt))

				switch Type(path), false
				{
				case 'string':
					if path ~= 'https?'
						msg.content.Push(OpenRouter.Chat.Message.addcontent(path ~= 'pdf$' ? 'pdf' : 'image_url', path))
					else
						msg.content.Push(OpenRouter.Chat.Message.addcontent('path', path))
				case 'array':
					for input in path
					{
						if input ~= 'https?'
							msg.content.Push(OpenRouter.Chat.Message.addcontent(input ~= 'pdf$' ? 'pdf' : 'image_url', input))
						else
							msg.content.Push(OpenRouter.Chat.Message.addcontent('path', input))
					}
				}

				data.Push(msg)
				return data
				isImageUrl(str) ; Checks for http(s):// or ftp:// and common image extensions at the end
				{
					if str ~= "i)^(https?|ftp)://[^\s/$.?#].[^\s]*\.(jpg|jpeg|png|gif|bmp|webp|tiff|tif)$"
						return 
					else
						return false
				}
			}

			; static addMsg(user,prompt,paths*)
			; {
			; 	msg := {role:'user',content:[]}
			; 	msg.content.Push(this.addcontent('text',prompt))

			; 	for path in paths
			; 	{
			; 		if path
			; 		&& FileExist(path)
			; 			msg.content.Push(this.addcontent('path',path))
			; 	}
			; 	this.data.push(msg)
			; }

			static addcontent(contenttype, input)
			{
				outobj := {}
				switch  contenttype, false
				{
				case 'text','prompt':
					outobj.type := 'text'
					outobj.text := input
				case 'image_url':
					outobj.type := contenttype
					outobj.image_url := {url:input}
				case 'pdf':
					outobj.type := 'file'
					outobj.file := {
						filename: filename,
						file_data: input
					}
				case 'path':
					SplitPath(input, &fName,,&ext)
					mime_type := OpenRouter.GetMimeType(input)
					
					if mime_type ~= 'image' {
						; Defensive validation: ensure image format is supported before encoding
						if !OpenRouter.ValidateSupportedImageFormat(input)
							throw ValueError('Image format not supported. Supported formats: ' OpenRouter.GetSupportedFormatsString() ' File: ' input)
						outobj.type := 'image_url'
						outobj.image_url := {
							url: OpenRouter.FileToContentURL(input)
						}
					} else if mime_type ~= 'audio' {
						outobj.type := 'input_audio'
						outobj.input_audio := {
							data: OpenRouter.FileToBase64(input),
							format: ext
						}
					} else if mime_type ~= 'text' {
						outobj.type := 'text'
						outobj.text := 'User Attachment (' fName '):`n`n' FileRead(input, 'utf-8')
					} else {
						SplitPath(input, &filename)
						outobj.type := 'file'
						outobj.file := {
							filename: filename,
							file_data: OpenRouter.FileToContentURL(input)
						}
					}
				default:
					throw ValueError('invalid contenttype. Expected text, prompt, image_url, pdf or path but got: ' contenttype)
				}
				return outobj
			}
		}
	}

	class Response {
		__New(http) {
			this.Status         := Number(http.Status)
			this.StatusText     := http.StatusText
			this.ResponseBody   := http.ResponseBody
			this.ResponseStream := http.ResponseStream
			this.ResponseHeaders:= http.GetAllResponseHeaders()
			this.ResponseText   := ConvertSafeArraytoUTF8(http.ResponseBody)
			return

			ConvertSafeArraytoUTF8(safe_array)
			{
				; Convert the response body to UTF-8
				responseBody := safe_array
				size := responseBody.MaxIndex() + 1
				rawBuffer := Buffer(size)
				DllCall("OleAut32.dll\SafeArrayAccessData", "Ptr", ComObjValue(responseBody), "Ptr*", &pdata:=0)
				DllCall("RtlMoveMemory", "Ptr", rawBuffer.Ptr, "Ptr", pdata, "Ptr", size)
				DllCall("OleAut32.dll\SafeArrayUnaccessData", "Ptr", ComObjValue(responseBody))
				return utf8 := StrGet(rawBuffer, "UTF-8")
			}
		}
	}

	static FileToBase64(path) {
		static crypt   := (%"Windows"%).Security.Cryptography.CryptographicBuffer
		static storage := (%"Windows"%).Storage.StorageFile

		if !(path is String)
			throw TypeError('expected path to be a String', -2, 'got: ' Type(path))
		if !FileExist(path)
			throw TargetError('file does not exist')

		img_file := OpenRouter.Await(storage.GetFileFromPathAsync(path))
		buff     := OpenRouter.Await((%"Windows"%).Storage.FileIO.ReadBufferAsync(img_file))
		return crypt.EncodeToBase64String(buff)
	}

	static FileToContentURL(path){
		base64img := OpenRouter.FileToBase64(path)
		mime_type := OpenRouter.GetMimeType(path)
		return Format('data:{};base64,{}', mime_type, base64img)

	}

	static GetMimeType(filePath)
	{
		static magic_numbers := Map(
			"123", {
				signs: ["0,00001A00051004"],
				mime: "application/vnd.lotus-1-2-3"
			},
			"cpl", {
				signs: [
				"0,4D5A",
				"0,DCDC"
				],
				mime: "application/cpl+xml"
			},
			"epub", {
				signs: ["0,504B03040A000200"],
				mime: "application/epub+zip"
			},
			"ttf", {
				signs: ["0,0001000000"],
				mime: "application/font-sfnt"
			},
			"gz", {
				signs: ["0,1F8B08"],
				mime: "application/gzip"
			},
			"tgz", {
				signs: ["0,1F8B08"],
				mime: "application/gzip"
			},
			"hqx", {
				signs: ["0,28546869732066696C65206D75737420626520636F6E76657274656420776974682042696E48657820"],
				mime: "application/mac-binhex40"
			},
			"doc", {
				signs: [
				"0,0D444F43",
				"0,CF11E0A1B11AE100",
				"0,D0CF11E0A1B11AE1",
				"0,DBA52D00",
				"512,ECA5C100"
				],
				mime: "application/msword"
			},
			"mxf", {
				signs: [
				"0,060E2B34020501010D0102010102",
				"0,3C435472616E7354696D656C696E653E"
				],
				mime: "application/mxf"
			},
			"lha", {
				signs: ["2,2D6C68"],
				mime: "application/octet-stream"
			},
			"lzh", {
				signs: ["2,2D6C68"],
				mime: "application/octet-stream"
			},
			"exe", {
				signs: ["0,4D5A"],
				mime: "application/octet-stream"
			},
			"class", {
				signs: ["0,CAFEBABE"],
				mime: "application/octet-stream"
			},
			"dll", {
				signs: ["0,4D5A"],
				mime: "application/octet-stream"
			},
			"img", {
				signs: [
				"0,000100005374616E64617264204A6574204442",
				"0,504943540008",
				"0,514649FB",
				"0,53434D49",
				"0,7E742C015070024D52010000000800000001000031000000310000004301FF0001000800010000007e742c01",
				"0,EB3C902A"
				],
				mime: "application/octet-stream"
			},
			"iso", {
				signs: [
				"32769,4344303031",
				"34817,4344303031",
				"36865,4344303031"
				],
				mime: "application/octet-stream"
			},
			"ogx", {
				signs: ["0,4F67675300020000000000000000"],
				mime: "application/ogg"
			},
			"oxps", {
				signs: ["0,504B0304"],
				mime: "application/oxps"
			},
			"pdf", {
				signs: ["0,25504446"],
				mime: "application/pdf"
			},
			"p10", {
				signs: ["0,64000000"],
				mime: "application/pkcs10"
			},
			"pls", {
				signs: ["0,5B706C61796C6973745D"],
				mime: "application/pls+xml"
			},
			"eps", {
				signs: [
				"0,252150532D41646F62652D332E3020455053462D332030",
				"0,C5D0D3C6"
				],
				mime: "application/postscript"
			},
			"ai", {
				signs: ["0,25504446"],
				mime: "application/postscript"
			},
			"rtf", {
				signs: ["0,7B5C72746631"],
				mime: "application/rtf"
			},
			"tsa", {
				signs: ["0,47"],
				mime: "application/tamp-sequence-adjust"
			},
			"msf", {
				signs: ["0,2F2F203C212D2D203C6D64623A6D6F726B3A7A"],
				mime: "application/vnd.epson.msf"
			},
			"fdf", {
				signs: ["0,25504446"],
				mime: "application/vnd.fdf"
			},
			"fm", {
				signs: ["0,3C4D616B657246696C6520"],
				mime: "application/vnd.framemaker"
			},
			"kmz", {
				signs: ["0,504B0304"],
				mime: "application/vnd.google-earth.kmz"
			},
			"tpl", {
				signs: [
				"0,0020AF30",
				"0,6D7346696C7465724C697374"
				],
				mime: "application/vnd.groove-tool-template"
			},
			"kwd", {
				signs: ["0,504B0304"],
				mime: "application/vnd.kde.kword"
			},
			"wk4", {
				signs: ["0,00001A000210040000000000"],
				mime: "application/vnd.lotus-1-2-3"
			},
			"wk3", {
				signs: ["0,00001A000010040000000000"],
				mime: "application/vnd.lotus-1-2-3"
			},
			"wk1", {
				signs: ["0,0000020006040600080000000000"],
				mime: "application/vnd.lotus-1-2-3"
			},
			"apr", {
				signs: ["0,D0CF11E0A1B11AE1"],
				mime: "application/vnd.lotus-approach"
			},
			"nsf", {
				signs: [
				"0,1A0000040000",
				"0,4E45534D1A01"
				],
				mime: "application/vnd.lotus-notes"
			},
			"ntf", {
				signs: [
				"0,1A0000",
				"0,30314F52444E414E43452053555256455920202020202020",
				"0,4E49544630"
				],
				mime: "application/vnd.lotus-notes"
			},
			"org", {
				signs: ["0,414F4C564D313030"],
				mime: "application/vnd.lotus-organizer"
			},
			"lwp", {
				signs: ["0,576F726450726F"],
				mime: "application/vnd.lotus-wordpro"
			},
			"sam", {
				signs: ["0,5B50686F6E655D"],
				mime: "application/vnd.lotus-wordpro"
			},
			"mif", {
				signs: [
				"0,3C4D616B657246696C6520",
				"0,56657273696F6E20"
				],
				mime: "application/vnd.mif"
			},
			"xul", {
				signs: ["0,3C3F786D6C2076657273696F6E3D22312E30223F3E"],
				mime: "application/vnd.mozilla.xul+xml"
			},
			"asf", {
				signs: ["0,3026B2758E66CF11A6D900AA0062CE6C"],
				mime: "application/vnd.ms-asf"
			},
			"cab", {
				signs: [
				"0,49536328",
				"0,4D534346"
				],
				mime: "application/vnd.ms-cab-compressed"
			},
			"xls", {
				signs: [
				"512,0908100000060500",
				"0,D0CF11E0A1B11AE1",
				"512,FDFFFFFF04",
				"512,FDFFFFFF20000000"
				],
				mime: "application/vnd.ms-excel"
			},
			"xla", {
				signs: ["0,D0CF11E0A1B11AE1"],
				mime: "application/vnd.ms-excel"
			},
			"chm", {
				signs: ["0,49545346"],
				mime: "application/vnd.ms-htmlhelp"
			},
			"ppt", {
				signs: [
				"512,006E1EF0",
				"512,0F00E803",
				"512,A0461DF0",
				"0,D0CF11E0A1B11AE1",
				"512,FDFFFFFF04"
				],
				mime: "application/vnd.ms-powerpoint"
			},
			"pps", {
				signs: ["0,D0CF11E0A1B11AE1"],
				mime: "application/vnd.ms-powerpoint"
			},
			"wks", {
				signs: [
				"0,0E574B53",
				"0,FF000200040405540200"
				],
				mime: "application/vnd.ms-works"
			},
			"wpl", {
				signs: ["84,4D6963726F736F66742057696E646F7773204D6564696120506C61796572202D2D20"],
				mime: "application/vnd.ms-wpl"
			},
			"xps", {
				signs: ["0,504B0304"],
				mime: "application/vnd.ms-xpsdocument"
			},
			"cif", {
				signs: ["2,5B56657273696F6E"],
				mime: "application/vnd.multiad.creator.cif"
			},
			"odp", {
				signs: ["0,504B0304"],
				mime: "application/vnd.oasis.opendocument.presentation"
			},
			"odt", {
				signs: ["0,504B0304"],
				mime: "application/vnd.oasis.opendocument.text"
			},
			"ott", {
				signs: ["0,504B0304"],
				mime: "application/vnd.oasis.opendocument.text-template"
			},
			"pptx", {
				signs: ["0,504B030414000600"],
				mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
			},
			"xlsx", {
				signs: ["0,504B030414000600"],
				mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
			},
			"docx", {
				signs: ["0,504B030414000600"],
				mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
			},
			"prc", {
				signs: [
				"0,424F4F4B4D4F4249",
				"60,74424D504B6E5772"
				],
				mime: "application/vnd.palm"
			},
			"pdb", {
				signs: [
				"11,000000000000000000000000000000000000000000000000",
				"0,4D2D5720506F636B6574204469637469",
				"0,4D6963726F736F667420432F432B2B20",
				"0,736D5F",
				"0,737A657A",
				"0,ACED0005737200126267626C69747A2E"
				],
				mime: "application/vnd.palm"
			},
			"qxd", {
				signs: ["0,00004D4D585052"],
				mime: "application/vnd.Quark.QuarkXPress"
			},
			"rar", {
				signs: [
				"0,526172211A0700",
				"0,526172211A070100"
				],
				mime: "application/vnd.rar"
			},
			"mmf", {
				signs: ["0,4D4D4D440000"],
				mime: "application/vnd.smaf"
			},
			"cap", {
				signs: [
				"0,52545353",
				"0,58435000"
				],
				mime: "application/vnd.tcpdump.pcap"
			},
			"dmp", {
				signs: [
				"0,4D444D5093A7",
				"0,5041474544553634",
				"0,5041474544554D50"
				],
				mime: "application/vnd.tcpdump.pcap"
			},
			"wpd", {
				signs: ["0,FF575043"],
				mime: "application/vnd.wordperfect"
			},
			"xar", {
				signs: ["0,78617221"],
				mime: "application/vnd.xara"
			},
			"spf", {
				signs: ["0,5350464900"],
				mime: "application/vnd.yamaha.smaf-phrase"
			},
			"dtd", {
				signs: ["0,0764743264647464"],
				mime: "application/xml-dtd"
			},
			"zip", {
				signs: [
				"0,504B0304",
				"0,504B0304",
				"0,504B030414000100630000000000",
				"0,504B0708",
				"30,504B4C495445",
				"526,504B537058",
				"29152,57696E5A6970"
				],
				mime: "application/zip"
			},
			"amr", {
				signs: ["0,2321414D52"],
				mime: "audio/AMR"
			},
			"au", {
				signs: [
				"0,2E736E64",
				"0,646E732E"
				],
				mime: "audio/basic"
			},
			"m4a", {
				signs: [
				"0,00000020667479704D344120",
				"4,667479704D344120"
				],
				mime: "audio/mp4"
			},
			"mp3", {
				signs: [
				"0,494433",
				"0,FFFB"
				],
				mime: "audio/mpeg"
			},
			"oga", {
				signs: ["0,4F67675300020000000000000000"],
				mime: "audio/ogg"
			},
			"ogg", {
				signs: ["0,4F67675300020000000000000000"],
				mime: "audio/ogg"
			},
			"qcp", {
				signs: ["0,52494646"],
				mime: "audio/qcelp"
			},
			"koz", {
				signs: ["0,49443303000000"],
				mime: "audio/vnd.audikoz"
			},
			"bmp", {
				signs: ["0,424D"],
				mime: "image/bmp"
			},
			"dib", {
				signs: ["0,424D"],
				mime: "image/bmp"
			},
			"emf", {
				signs: ["0,01000000"],
				mime: "image/emf"
			},
			"fits", {
				signs: ["0,53494D504C4520203D202020202020202020202020202020202020202054"],
				mime: "image/fits"
			},
			"gif", {
				signs: ["0,474946383961"],
				mime: "image/gif"
			},
			"jp2", {
				signs: ["0,0000000C6A5020200D0A"],
				mime: "image/jp2"
			},
			"jpg", {
				signs: ["0,FFD8"],
				mime: "image/jpeg"
			},
			"jpeg", {
				signs: ["0,FFD8"],
				mime: "image/jpeg"
			},
			"jpe", {
				signs: ["0,FFD8"],
				mime: "image/jpeg"
			},
			"jfif", {
				signs: ["0,FFD8"],
				mime: "image/jpeg"
			},
			"png", {
				signs: ["0,89504E470D0A1A0A"],
				mime: "image/png"
			},
			"tiff", {
				signs: [
				"0,492049",
				"0,49492A00",
				"0,4D4D002A",
				"0,4D4D002B"
				],
				mime: "image/tiff"
			},
			"tif", {
				signs: [
				"0,492049",
				"0,49492A00",
				"0,4D4D002A",
				"0,4D4D002B"
				],
				mime: "image/tiff"
			},
			"psd", {
				signs: ["0,38425053"],
				mime: "image/vnd.adobe.photoshop"
			},
			"dwg", {
				signs: ["0,41433130"],
				mime: "image/vnd.dwg"
			},
			"ico", {
				signs: ["0,00000100"],
				mime: "image/vnd.microsoft.icon"
			},
			"mdi", {
				signs: ["0,4550"],
				mime: "image/vnd.ms-modi"
			},
			"hdr", {
				signs: [
				"0,233F52414449414E43450A",
				"0,49536328"
				],
				mime: "image/vnd.radiance"
			},
			"pcx", {
				signs: ["512,0908100000060500"],
				mime: "image/vnd.zbrush.pcx"
			},
			"wmf", {
				signs: [
				"0,010009000003",
				"0,D7CDC69A"
				],
				mime: "image/wmf"
			},
			"eml", {
				signs: [
				"0,46726F6D3A20",
				"0,52657475726E2D506174683A20",
				"0,582D"
				],
				mime: "message/rfc822"
			},
			"art", {
				signs: ["0,4A47040E"],
				mime: "message/rfc822"
			},
			"manifest", {
				signs: ["0,3C3F786D6C2076657273696F6E3D"],
				mime: "text/cache-manifest"
			},
			"log", {
				signs: ["0,2A2A2A2020496E7374616C6C6174696F6E205374617274656420"],
				mime: "text/plain"
			},
			"tsv", {
				signs: ["0,47"],
				mime: "text/tab-separated-values"
			},
			"vcf", {
				signs: ["0,424547494E3A56434152440D0A"],
				mime: "text/vcard"
			},
			"dms", {
				signs: ["0,444D5321"],
				mime: "text/vnd.DMClientScript"
			},
			"dot", {
				signs: ["0,D0CF11E0A1B11AE1"],
				mime: "text/vnd.graphviz"
			},
			"ts", {
				signs: ["0,47"],
				mime: "text/vnd.trolltech.linguist"
			},
			"3gp", {
				signs: [
				"0,0000001466747970336770",
				"0,0000002066747970336770"
				],
				mime: "video/3gpp"
			},
			"3g2", {
				signs: [
				"0,0000001466747970336770",
				"0,0000002066747970336770"
				],
				mime: "video/3gpp2"
			},
			"mp4", {
				signs: [
				"0,000000146674797069736F6D",
				"0,000000186674797033677035",
				"0,0000001C667479704D534E56012900464D534E566D703432",
				"4,6674797033677035",
				"4,667479704D534E56",
				"4,6674797069736F6D"
				],
				mime: "video/mp4"
			},
			"m4v", {
				signs: [
				"0,00000018667479706D703432",
				"0,00000020667479704D345620",
				"4,667479706D703432"
				],
				mime: "video/mp4"
			},
			"mpeg", {
				signs: [
				"0,00000100",
				"0,FFD8"
				],
				mime: "video/mpeg"
			},
			"mpg", {
				signs: [
				"0,00000100",
				"0,000001BA",
				"0,FFD8"
				],
				mime: "video/mpeg"
			},
			"ogv", {
				signs: ["0,4F67675300020000000000000000"],
				mime: "video/ogg"
			},
			"mov", {
				signs: [
				"0,00",
				"0,000000146674797071742020",
				"4,6674797071742020",
				"4,6D6F6F76"
				],
				mime: "video/quicktime"
			},
			"cpt", {
				signs: [
				"0,4350543746494C45",
				"0,43505446494C45"
				],
				mime: "application/mac-compactpro"
			},
			"sxc", {
				signs: [
				"0,504B0304",
				"0,504B0304"
				],
				mime: "application/vnd.sun.xml.calc"
			},
			"sxd", {
				signs: ["0,504B0304"],
				mime: "application/vnd.sun.xml.draw"
			},
			"sxi", {
				signs: ["0,504B0304"],
				mime: "application/vnd.sun.xml.impress"
			},
			"sxw", {
				signs: ["0,504B0304"],
				mime: "application/vnd.sun.xml.writer"
			},
			"bz2", {
				signs: ["0,425A68"],
				mime: "application/x-bzip2"
			},
			"vcd", {
				signs: ["0,454E5452595643440200000102001858"],
				mime: "application/x-cdlink"
			},
			"csh", {
				signs: ["0,6375736800000002000000"],
				mime: "application/x-csh"
			},
			"spl", {
				signs: ["0,00000100"],
				mime: "application/x-futuresplash"
			},
			"jar", {
				signs: [
				"0,4A4152435300",
				"0,504B0304",
				"0,504B0304140008000800",
				"0,5F27A889"
				],
				mime: "application/x-java-archive"
			},
			"rpm", {
				signs: ["0,EDABEEDB"],
				mime: "application/x-rpm"
			},
			"swf", {
				signs: [
				"0,435753",
				"0,465753",
				"0,5A5753"
				],
				mime: "application/x-shockwave-flash"
			},
			"sit", {
				signs: [
				"0,5349542100",
				"0,5374756666497420286329313939372D"
				],
				mime: "application/x-stuffit"
			},
			"tar", {
				signs: ["257,7573746172"],
				mime: "application/x-tar"
			},
			"xpi", {
				signs: ["0,504B0304"],
				mime: "application/x-xpinstall"
			},
			"xz", {
				signs: ["0,FD377A585A00"],
				mime: "application/x-xz"
			},
			"mid", {
				signs: ["0,4D546864"],
				mime: "audio/midi"
			},
			"midi", {
				signs: ["0,4D546864"],
				mime: "audio/midi"
			},
			"aiff", {
				signs: ["0,464F524D00"],
				mime: "audio/x-aiff"
			},
			"flac", {
				signs: ["0,664C614300000022"],
				mime: "audio/x-flac"
			},
			"wma", {
				signs: ["0,3026B2758E66CF11A6D900AA0062CE6C"],
				mime: "audio/x-ms-wma"
			},
			"ram", {
				signs: ["0,727473703A2F2F"],
				mime: "audio/x-pn-realaudio"
			},
			"rm", {
				signs: ["0,2E524D46"],
				mime: "audio/x-pn-realaudio"
			},
			"ra", {
				signs: [
				"0,2E524D460000001200",
				"0,2E7261FD00"
				],
				mime: "audio/x-realaudio"
			},
			"wav", {
				signs: ["0,52494646"],
				mime: "audio/x-wav"
			},
			"webp", {
				signs: ["0,52494646"],
				mime: "image/webp"
			},
			"pgm", {
				signs: ["0,50350A"],
				mime: "image/x-portable-graymap"
			},
			"rgb", {
				signs: ["0,01DA01010003"],
				mime: "image/x-rgb"
			},
			"webm", {
				signs: ["0,1A45DFA3"],
				mime: "video/webm"
			},
			"flv", {
				signs: [
				"0,00000020667479704D345620",
				"0,464C5601"
				],
				mime: "video/x-flv"
			},
			"mkv", {
				signs: ["0,1A45DFA3"],
				mime: "video/x-matroska"
			},
			"asx", {
				signs: ["0,3C"],
				mime: "video/x-ms-asf"
			},
			"wmv", {
				signs: ["0,3026B2758E66CF11A6D900AA0062CE6C"],
				mime: "video/x-ms-wmv"
			},
			"avi", {
				signs: ["0,52494646"],
				mime: "video/x-msvideo"
			}
		)

		SplitPath filePath,,, &ext
		ext := StrLower(ext)

		try {
			; Check for magic numbers
			try {
				file := FileOpen(filePath, "r")

				if magic_numbers.Has(ext)
				{
					for sign in magic_numbers[ext].signs
					{
						offset := StrSplit(sign, ",")[1]
						signature := StrSplit(sign, ",")[2]
						file.Seek(offset)

						loop StrLen(signature) // 2
							bytes .= Format('{:02X}', file.ReadUChar())

						if bytes == signature
							return magic_numbers[ext].mime
					}
				}
			}
			catch Error as e
				throw e
			finally
				file.Close()

			; If no match, check for text files
			try {
				file := FileOpen(filePath, "r")
				isText := true
				loop 16 {
					int64 .= file.ReadInt64()
					if !(int64 ~= '00') ; doesnt contain null byte
						continue
					isText := false
					break
				}

				if isText
					return "text/plain"
			}
			catch Error as e
				throw e
			finally
				file.Close()
		}
		catch as err {
			; If there's an error reading the file, default to octet-stream
			return "application/octet-stream"
		}

		; Use file extension as a backup if magic numbers don't match
		switch ext
		{
		case 'aac'   : return 'audio/aac'
		case 'abw'   : return 'application/x-abiword'
		case 'apng'  : return 'image/apng'
		case 'arc'   : return 'application/x-freearc'
		case 'avif'  : return 'image/avif'
		case 'avi'   : return 'video/x-msvideo'
		case 'azw'   : return 'application/vnd.amazon.ebook'
		case 'bin'   : return 'application/octet-stream'
		case 'bmp'   : return 'image/bmp'
		case 'bz'    : return 'application/x-bzip'
		case 'bz2'   : return 'application/x-bzip2'
		case 'cda'   : return 'application/x-cdf'
		case 'csh'   : return 'application/x-csh'
		case 'css'   : return 'text/css'
		case 'csv'   : return 'text/csv'
		case 'doc'   : return 'application/msword'
		case 'docx'  : return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
		case 'eot'   : return 'application/vnd.ms-fontobject'
		case 'epub'  : return 'application/epub+zip'
		case 'gz'    : return 'application/gzip'
		case 'gif'   : return 'image/gif'
		case 'html'  : return 'text/html'
		case 'htm'   : return 'text/html'
		case 'ico'   : return 'image/vnd.microsoft.icon'
		case 'ics'   : return 'text/calendar'
		case 'jar'   : return 'application/java-archive'
		case 'jpeg'  : return 'image/jpeg'
		case 'jpg'   : return 'image/jpeg'
		case 'js'    : return 'text/javascript'
		case 'json'  : return 'application/json'
		case 'jsonld': return 'application/ld+json'
		case 'mid'   : return 'audio/midi, audio/x-midi'
		case 'midi'  : return 'audio/midi, audio/x-midi'
		case 'mjs'   : return 'text/javascript'
		case 'mp3'   : return 'audio/mpeg'
		case 'mp4'   : return 'video/mp4'
		case 'mpeg'  : return 'video/mpeg'
		case 'mpkg'  : return 'application/vnd.apple.installer+xml'
		case 'odp'   : return 'application/vnd.oasis.opendocument.presentation'
		case 'ods'   : return 'application/vnd.oasis.opendocument.spreadsheet'
		case 'odt'   : return 'application/vnd.oasis.opendocument.text'
		case 'oga'   : return 'audio/ogg'
		case 'ogv'   : return 'video/ogg'
		case 'ogx'   : return 'application/ogg'
		case 'opus'  : return 'audio/ogg'
		case 'otf'   : return 'font/otf'
		case 'png'   : return 'image/png'
		case 'pdf'   : return 'application/pdf'
		case 'php'   : return 'application/x-httpd-php'
		case 'ppt'   : return 'application/vnd.ms-powerpoint'
		case 'pptx'  : return 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
		case 'rar'   : return 'application/vnd.rar'
		case 'rtf'   : return 'application/rtf'
		case 'sh'    : return 'application/x-sh'
		case 'svg'   : return 'image/svg+xml'
		case 'tar'   : return 'application/x-tar'
		case 'tif'   : return 'image/tiff'
		case 'tiff'  : return 'image/tiff'
		case 'ts'    : return 'video/mp2t'
		case 'ttf'   : return 'font/ttf'
		case 'txt'   : return 'text/plain'
		case 'vsd'   : return 'application/vnd.visio'
		case 'wav'   : return 'audio/wav'
		case 'weba'  : return 'audio/webm'
		case 'webm'  : return 'video/webm'
		case 'webp'  : return 'image/webp'
		case 'woff'  : return 'font/woff'
		case 'woff2' : return 'font/woff2'
		case 'xhtml' : return 'application/xhtml+xml'
		case 'xls'   : return 'application/vnd.ms-excel'
		case 'xlsx'  : return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
		case 'xml'   : return 'application/xml'
		case 'xul'   : return 'application/vnd.mozilla.xul+xml'
		case 'zip'   : return 'application/zip'
		case '3gp'   : return 'video/3gpp'
		case '3g2'   : return 'video/3gpp2'
		case '7z'    : return 'application/x-7z-compressed'
		default      : return "application/octet-stream"
		}
	}

	static Await(async) {
		status := (%"Windows"%).Foundation.AsyncStatus
		while async.Status = status.Started
			Sleep 10
		if async.Status = status.Error {
			OutputDebug async.ErrorCode.value '`n'
			throw async.ErrorCode
		}
		try return async.GetResults()
		catch
			return
	}
	static ValidateSupportedImageFormat(filePath)
	{
		static SUPPORTED_IMAGE_FORMATS := ['jpeg', 'jpg', 'png', 'gif', 'webp']
		static SUPPORTED_IMAGE_MIME_TYPES := ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
		
		if !FileExist(filePath)
			return false
		
		SplitPath(filePath, , , &ext)
		ext := StrLower(ext)
		
		; Check file extension first (fast path)
		if ext {
			for fmt in SUPPORTED_IMAGE_FORMATS {
				if fmt = ext {
					; DebugLog("Image validation - extension match: " ext)
					return true
				}
			}
		}
		
		; Fall back to MIME type detection
		mime_type := OpenRouter.GetMimeType(filePath)
		; DebugLog("Image validation - extension: " ext ", MIME type: " mime_type " from file: " filePath)
		
		for mime in SUPPORTED_IMAGE_MIME_TYPES {
			if mime = mime_type {
				; DebugLog("Image validation - MIME type match: " mime_type)
				return true
			}
		}
		; DebugLog("Image validation FAILED - MIME type not in supported list: " mime_type)
		return false
	}
	
	
	static GetSupportedFormatsString()
	{
		return 'JPEG, PNG, GIF, WebP'
	}
}

