(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // node_modules/jssip/package.json
  var require_package = __commonJS({
    "node_modules/jssip/package.json"(exports, module) {
      module.exports = {
        name: "jssip",
        title: "JsSIP",
        description: "the Javascript SIP library",
        version: "3.10.1",
        homepage: "https://jssip.net",
        contributors: [
          "Jos\xE9 Luis Mill\xE1n <jmillan@aliax.net> (https://github.com/jmillan)",
          "I\xF1aki Baz Castillo <ibc@aliax.net> (https://inakibaz.me)"
        ],
        types: "lib/JsSIP.d.ts",
        main: "lib-es5/JsSIP.js",
        keywords: [
          "sip",
          "websocket",
          "webrtc",
          "node",
          "browser",
          "library"
        ],
        license: "MIT",
        repository: {
          type: "git",
          url: "https://github.com/versatica/JsSIP.git"
        },
        bugs: {
          url: "https://github.com/versatica/JsSIP/issues"
        },
        dependencies: {
          "@types/events": "^3.0.0",
          "@types/debug": "^4.1.7",
          debug: "^4.3.1",
          events: "^3.3.0",
          "sdp-transform": "^2.14.1"
        },
        devDependencies: {
          "@babel/core": "^7.19.6",
          "@babel/preset-env": "^7.19.4",
          "ansi-colors": "^3.2.4",
          browserify: "^16.5.1",
          eslint: "^5.16.0",
          "fancy-log": "^1.3.3",
          gulp: "^4.0.2",
          "gulp-babel": "^8.0.0",
          "gulp-eslint": "^5.0.0",
          "gulp-expect-file": "^1.0.2",
          "gulp-header": "^2.0.9",
          "gulp-nodeunit-runner": "^0.2.2",
          "gulp-plumber": "^1.2.1",
          "gulp-rename": "^1.4.0",
          "gulp-uglify-es": "^1.0.4",
          pegjs: "^0.7.0",
          "vinyl-buffer": "^1.0.1",
          "vinyl-source-stream": "^2.0.0"
        },
        scripts: {
          lint: "node npm-scripts.js lint",
          test: "node npm-scripts.js test",
          prepublish: "node npm-scripts.js prepublish",
          release: "node npm-scripts.js release"
        }
      };
    }
  });

  // node_modules/jssip/lib-es5/Constants.js
  var require_Constants = __commonJS({
    "node_modules/jssip/lib-es5/Constants.js"(exports, module) {
      "use strict";
      var pkg = require_package();
      module.exports = {
        USER_AGENT: "".concat(pkg.title, " ").concat(pkg.version),
        // SIP scheme.
        SIP: "sip",
        SIPS: "sips",
        // End and Failure causes.
        causes: {
          // Generic error causes.
          CONNECTION_ERROR: "Connection Error",
          REQUEST_TIMEOUT: "Request Timeout",
          SIP_FAILURE_CODE: "SIP Failure Code",
          INTERNAL_ERROR: "Internal Error",
          // SIP error causes.
          BUSY: "Busy",
          REJECTED: "Rejected",
          REDIRECTED: "Redirected",
          UNAVAILABLE: "Unavailable",
          NOT_FOUND: "Not Found",
          ADDRESS_INCOMPLETE: "Address Incomplete",
          INCOMPATIBLE_SDP: "Incompatible SDP",
          MISSING_SDP: "Missing SDP",
          AUTHENTICATION_ERROR: "Authentication Error",
          // Session error causes.
          BYE: "Terminated",
          WEBRTC_ERROR: "WebRTC Error",
          CANCELED: "Canceled",
          NO_ANSWER: "No Answer",
          EXPIRES: "Expires",
          NO_ACK: "No ACK",
          DIALOG_ERROR: "Dialog Error",
          USER_DENIED_MEDIA_ACCESS: "User Denied Media Access",
          BAD_MEDIA_DESCRIPTION: "Bad Media Description",
          RTP_TIMEOUT: "RTP Timeout"
        },
        SIP_ERROR_CAUSES: {
          REDIRECTED: [300, 301, 302, 305, 380],
          BUSY: [486, 600],
          REJECTED: [403, 603],
          NOT_FOUND: [404, 604],
          UNAVAILABLE: [480, 410, 408, 430],
          ADDRESS_INCOMPLETE: [484, 424],
          INCOMPATIBLE_SDP: [488, 606],
          AUTHENTICATION_ERROR: [401, 407]
        },
        // SIP Methods.
        ACK: "ACK",
        BYE: "BYE",
        CANCEL: "CANCEL",
        INFO: "INFO",
        INVITE: "INVITE",
        MESSAGE: "MESSAGE",
        NOTIFY: "NOTIFY",
        OPTIONS: "OPTIONS",
        REGISTER: "REGISTER",
        REFER: "REFER",
        UPDATE: "UPDATE",
        SUBSCRIBE: "SUBSCRIBE",
        // DTMF transport methods.
        DTMF_TRANSPORT: {
          INFO: "INFO",
          RFC2833: "RFC2833"
        },
        /* SIP Response Reasons
         * DOC: https://www.iana.org/assignments/sip-parameters
         * Copied from https://github.com/versatica/OverSIP/blob/master/lib/oversip/sip/constants.rb#L7
         */
        REASON_PHRASE: {
          100: "Trying",
          180: "Ringing",
          181: "Call Is Being Forwarded",
          182: "Queued",
          183: "Session Progress",
          199: "Early Dialog Terminated",
          // draft-ietf-sipcore-199
          200: "OK",
          202: "Accepted",
          // RFC 3265
          204: "No Notification",
          // RFC 5839
          300: "Multiple Choices",
          301: "Moved Permanently",
          302: "Moved Temporarily",
          305: "Use Proxy",
          380: "Alternative Service",
          400: "Bad Request",
          401: "Unauthorized",
          402: "Payment Required",
          403: "Forbidden",
          404: "Not Found",
          405: "Method Not Allowed",
          406: "Not Acceptable",
          407: "Proxy Authentication Required",
          408: "Request Timeout",
          410: "Gone",
          412: "Conditional Request Failed",
          // RFC 3903
          413: "Request Entity Too Large",
          414: "Request-URI Too Long",
          415: "Unsupported Media Type",
          416: "Unsupported URI Scheme",
          417: "Unknown Resource-Priority",
          // RFC 4412
          420: "Bad Extension",
          421: "Extension Required",
          422: "Session Interval Too Small",
          // RFC 4028
          423: "Interval Too Brief",
          424: "Bad Location Information",
          // RFC 6442
          428: "Use Identity Header",
          // RFC 4474
          429: "Provide Referrer Identity",
          // RFC 3892
          430: "Flow Failed",
          // RFC 5626
          433: "Anonymity Disallowed",
          // RFC 5079
          436: "Bad Identity-Info",
          // RFC 4474
          437: "Unsupported Certificate",
          // RFC 4744
          438: "Invalid Identity Header",
          // RFC 4744
          439: "First Hop Lacks Outbound Support",
          // RFC 5626
          440: "Max-Breadth Exceeded",
          // RFC 5393
          469: "Bad Info Package",
          // draft-ietf-sipcore-info-events
          470: "Consent Needed",
          // RFC 5360
          478: "Unresolvable Destination",
          // Custom code copied from Kamailio.
          480: "Temporarily Unavailable",
          481: "Call/Transaction Does Not Exist",
          482: "Loop Detected",
          483: "Too Many Hops",
          484: "Address Incomplete",
          485: "Ambiguous",
          486: "Busy Here",
          487: "Request Terminated",
          488: "Not Acceptable Here",
          489: "Bad Event",
          // RFC 3265
          491: "Request Pending",
          493: "Undecipherable",
          494: "Security Agreement Required",
          // RFC 3329
          500: "JsSIP Internal Error",
          501: "Not Implemented",
          502: "Bad Gateway",
          503: "Service Unavailable",
          504: "Server Time-out",
          505: "Version Not Supported",
          513: "Message Too Large",
          580: "Precondition Failure",
          // RFC 3312
          600: "Busy Everywhere",
          603: "Decline",
          604: "Does Not Exist Anywhere",
          606: "Not Acceptable"
        },
        ALLOWED_METHODS: "INVITE,ACK,CANCEL,BYE,UPDATE,MESSAGE,OPTIONS,REFER,INFO,NOTIFY",
        ACCEPTED_BODY_TYPES: "application/sdp, application/dtmf-relay",
        MAX_FORWARDS: 69,
        SESSION_EXPIRES: 90,
        MIN_SESSION_EXPIRES: 60,
        CONNECTION_RECOVERY_MAX_INTERVAL: 30,
        CONNECTION_RECOVERY_MIN_INTERVAL: 2
      };
    }
  });

  // node_modules/jssip/lib-es5/Exceptions.js
  var require_Exceptions = __commonJS({
    "node_modules/jssip/lib-es5/Exceptions.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _wrapNativeSuper(Class) {
        var _cache = typeof Map === "function" ? /* @__PURE__ */ new Map() : void 0;
        _wrapNativeSuper = function _wrapNativeSuper2(Class2) {
          if (Class2 === null || !_isNativeFunction(Class2)) return Class2;
          if (typeof Class2 !== "function") {
            throw new TypeError("Super expression must either be null or a function");
          }
          if (typeof _cache !== "undefined") {
            if (_cache.has(Class2)) return _cache.get(Class2);
            _cache.set(Class2, Wrapper);
          }
          function Wrapper() {
            return _construct(Class2, arguments, _getPrototypeOf(this).constructor);
          }
          Wrapper.prototype = Object.create(Class2.prototype, { constructor: { value: Wrapper, enumerable: false, writable: true, configurable: true } });
          return _setPrototypeOf(Wrapper, Class2);
        };
        return _wrapNativeSuper(Class);
      }
      function _construct(Parent, args, Class) {
        if (_isNativeReflectConstruct()) {
          _construct = Reflect.construct;
        } else {
          _construct = function _construct2(Parent2, args2, Class2) {
            var a = [null];
            a.push.apply(a, args2);
            var Constructor = Function.bind.apply(Parent2, a);
            var instance = new Constructor();
            if (Class2) _setPrototypeOf(instance, Class2.prototype);
            return instance;
          };
        }
        return _construct.apply(null, arguments);
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _isNativeFunction(fn) {
        return Function.toString.call(fn).indexOf("[native code]") !== -1;
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var ConfigurationError = /* @__PURE__ */ function(_Error) {
        _inherits(ConfigurationError2, _Error);
        var _super = _createSuper(ConfigurationError2);
        function ConfigurationError2(parameter, value) {
          var _this;
          _classCallCheck(this, ConfigurationError2);
          _this = _super.call(this);
          _this.code = 1;
          _this.name = "CONFIGURATION_ERROR";
          _this.parameter = parameter;
          _this.value = value;
          _this.message = !_this.value ? "Missing parameter: ".concat(_this.parameter) : "Invalid value ".concat(JSON.stringify(_this.value), ' for parameter "').concat(_this.parameter, '"');
          return _this;
        }
        return ConfigurationError2;
      }(/* @__PURE__ */ _wrapNativeSuper(Error));
      var InvalidStateError = /* @__PURE__ */ function(_Error2) {
        _inherits(InvalidStateError2, _Error2);
        var _super2 = _createSuper(InvalidStateError2);
        function InvalidStateError2(status) {
          var _this2;
          _classCallCheck(this, InvalidStateError2);
          _this2 = _super2.call(this);
          _this2.code = 2;
          _this2.name = "INVALID_STATE_ERROR";
          _this2.status = status;
          _this2.message = "Invalid status: ".concat(status);
          return _this2;
        }
        return InvalidStateError2;
      }(/* @__PURE__ */ _wrapNativeSuper(Error));
      var NotSupportedError = /* @__PURE__ */ function(_Error3) {
        _inherits(NotSupportedError2, _Error3);
        var _super3 = _createSuper(NotSupportedError2);
        function NotSupportedError2(message) {
          var _this3;
          _classCallCheck(this, NotSupportedError2);
          _this3 = _super3.call(this);
          _this3.code = 3;
          _this3.name = "NOT_SUPPORTED_ERROR";
          _this3.message = message;
          return _this3;
        }
        return NotSupportedError2;
      }(/* @__PURE__ */ _wrapNativeSuper(Error));
      var NotReadyError = /* @__PURE__ */ function(_Error4) {
        _inherits(NotReadyError2, _Error4);
        var _super4 = _createSuper(NotReadyError2);
        function NotReadyError2(message) {
          var _this4;
          _classCallCheck(this, NotReadyError2);
          _this4 = _super4.call(this);
          _this4.code = 4;
          _this4.name = "NOT_READY_ERROR";
          _this4.message = message;
          return _this4;
        }
        return NotReadyError2;
      }(/* @__PURE__ */ _wrapNativeSuper(Error));
      module.exports = {
        ConfigurationError,
        InvalidStateError,
        NotSupportedError,
        NotReadyError
      };
    }
  });

  // node_modules/jssip/lib-es5/NameAddrHeader.js
  var require_NameAddrHeader = __commonJS({
    "node_modules/jssip/lib-es5/NameAddrHeader.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var URI = require_URI();
      var Grammar = require_Grammar();
      module.exports = /* @__PURE__ */ function() {
        _createClass(NameAddrHeader, null, [{
          key: "parse",
          /**
           * Parse the given string and returns a NameAddrHeader instance or undefined if
           * it is an invalid NameAddrHeader.
           */
          value: function parse(name_addr_header) {
            name_addr_header = Grammar.parse(name_addr_header, "Name_Addr_Header");
            if (name_addr_header !== -1) {
              return name_addr_header;
            } else {
              return void 0;
            }
          }
        }]);
        function NameAddrHeader(uri, display_name, parameters) {
          _classCallCheck(this, NameAddrHeader);
          if (!uri || !(uri instanceof URI)) {
            throw new TypeError('missing or invalid "uri" parameter');
          }
          this._uri = uri;
          this._parameters = {};
          this.display_name = display_name;
          for (var param in parameters) {
            if (Object.prototype.hasOwnProperty.call(parameters, param)) {
              this.setParam(param, parameters[param]);
            }
          }
        }
        _createClass(NameAddrHeader, [{
          key: "setParam",
          value: function setParam(key, value) {
            if (key) {
              this._parameters[key.toLowerCase()] = typeof value === "undefined" || value === null ? null : value.toString();
            }
          }
        }, {
          key: "getParam",
          value: function getParam(key) {
            if (key) {
              return this._parameters[key.toLowerCase()];
            }
          }
        }, {
          key: "hasParam",
          value: function hasParam(key) {
            if (key) {
              return this._parameters.hasOwnProperty(key.toLowerCase()) && true || false;
            }
          }
        }, {
          key: "deleteParam",
          value: function deleteParam(parameter) {
            parameter = parameter.toLowerCase();
            if (this._parameters.hasOwnProperty(parameter)) {
              var value = this._parameters[parameter];
              delete this._parameters[parameter];
              return value;
            }
          }
        }, {
          key: "clearParams",
          value: function clearParams() {
            this._parameters = {};
          }
        }, {
          key: "clone",
          value: function clone() {
            return new NameAddrHeader(this._uri.clone(), this._display_name, JSON.parse(JSON.stringify(this._parameters)));
          }
        }, {
          key: "_quote",
          value: function _quote(str) {
            return str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
          }
        }, {
          key: "toString",
          value: function toString() {
            var body = this._display_name ? '"'.concat(this._quote(this._display_name), '" ') : "";
            body += "<".concat(this._uri.toString(), ">");
            for (var parameter in this._parameters) {
              if (Object.prototype.hasOwnProperty.call(this._parameters, parameter)) {
                body += ";".concat(parameter);
                if (this._parameters[parameter] !== null) {
                  body += "=".concat(this._parameters[parameter]);
                }
              }
            }
            return body;
          }
        }, {
          key: "uri",
          get: function get() {
            return this._uri;
          }
        }, {
          key: "display_name",
          get: function get() {
            return this._display_name;
          },
          set: function set(value) {
            this._display_name = value === 0 ? "0" : value;
          }
        }]);
        return NameAddrHeader;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Grammar.js
  var require_Grammar = __commonJS({
    "node_modules/jssip/lib-es5/Grammar.js"(exports, module) {
      "use strict";
      module.exports = function() {
        function quote(s) {
          return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\x08/g, "\\b").replace(/\t/g, "\\t").replace(/\n/g, "\\n").replace(/\f/g, "\\f").replace(/\r/g, "\\r").replace(/[\x00-\x07\x0B\x0E-\x1F\x80-\uFFFF]/g, escape) + '"';
        }
        var result = {
          /*
           * Parses the input with a generated parser. If the parsing is successfull,
           * returns a value explicitly or implicitly specified by the grammar from
           * which the parser was generated (see |PEG.buildParser|). If the parsing is
           * unsuccessful, throws |PEG.parser.SyntaxError| describing the error.
           */
          parse: function parse(input, startRule) {
            var parseFunctions = {
              "CRLF": parse_CRLF,
              "DIGIT": parse_DIGIT,
              "ALPHA": parse_ALPHA,
              "HEXDIG": parse_HEXDIG,
              "WSP": parse_WSP,
              "OCTET": parse_OCTET,
              "DQUOTE": parse_DQUOTE,
              "SP": parse_SP,
              "HTAB": parse_HTAB,
              "alphanum": parse_alphanum,
              "reserved": parse_reserved,
              "unreserved": parse_unreserved,
              "mark": parse_mark,
              "escaped": parse_escaped,
              "LWS": parse_LWS,
              "SWS": parse_SWS,
              "HCOLON": parse_HCOLON,
              "TEXT_UTF8_TRIM": parse_TEXT_UTF8_TRIM,
              "TEXT_UTF8char": parse_TEXT_UTF8char,
              "UTF8_NONASCII": parse_UTF8_NONASCII,
              "UTF8_CONT": parse_UTF8_CONT,
              "LHEX": parse_LHEX,
              "token": parse_token,
              "token_nodot": parse_token_nodot,
              "separators": parse_separators,
              "word": parse_word,
              "STAR": parse_STAR,
              "SLASH": parse_SLASH,
              "EQUAL": parse_EQUAL,
              "LPAREN": parse_LPAREN,
              "RPAREN": parse_RPAREN,
              "RAQUOT": parse_RAQUOT,
              "LAQUOT": parse_LAQUOT,
              "COMMA": parse_COMMA,
              "SEMI": parse_SEMI,
              "COLON": parse_COLON,
              "LDQUOT": parse_LDQUOT,
              "RDQUOT": parse_RDQUOT,
              "comment": parse_comment,
              "ctext": parse_ctext,
              "quoted_string": parse_quoted_string,
              "quoted_string_clean": parse_quoted_string_clean,
              "qdtext": parse_qdtext,
              "quoted_pair": parse_quoted_pair,
              "SIP_URI_noparams": parse_SIP_URI_noparams,
              "SIP_URI": parse_SIP_URI,
              "uri_scheme": parse_uri_scheme,
              "uri_scheme_sips": parse_uri_scheme_sips,
              "uri_scheme_sip": parse_uri_scheme_sip,
              "userinfo": parse_userinfo,
              "user": parse_user,
              "user_unreserved": parse_user_unreserved,
              "password": parse_password,
              "hostport": parse_hostport,
              "host": parse_host,
              "hostname": parse_hostname,
              "domainlabel": parse_domainlabel,
              "toplabel": parse_toplabel,
              "IPv6reference": parse_IPv6reference,
              "IPv6address": parse_IPv6address,
              "h16": parse_h16,
              "ls32": parse_ls32,
              "IPv4address": parse_IPv4address,
              "dec_octet": parse_dec_octet,
              "port": parse_port,
              "uri_parameters": parse_uri_parameters,
              "uri_parameter": parse_uri_parameter,
              "transport_param": parse_transport_param,
              "user_param": parse_user_param,
              "method_param": parse_method_param,
              "ttl_param": parse_ttl_param,
              "maddr_param": parse_maddr_param,
              "lr_param": parse_lr_param,
              "other_param": parse_other_param,
              "pname": parse_pname,
              "pvalue": parse_pvalue,
              "paramchar": parse_paramchar,
              "param_unreserved": parse_param_unreserved,
              "headers": parse_headers,
              "header": parse_header,
              "hname": parse_hname,
              "hvalue": parse_hvalue,
              "hnv_unreserved": parse_hnv_unreserved,
              "Request_Response": parse_Request_Response,
              "Request_Line": parse_Request_Line,
              "Request_URI": parse_Request_URI,
              "absoluteURI": parse_absoluteURI,
              "hier_part": parse_hier_part,
              "net_path": parse_net_path,
              "abs_path": parse_abs_path,
              "opaque_part": parse_opaque_part,
              "uric": parse_uric,
              "uric_no_slash": parse_uric_no_slash,
              "path_segments": parse_path_segments,
              "segment": parse_segment,
              "param": parse_param,
              "pchar": parse_pchar,
              "scheme": parse_scheme,
              "authority": parse_authority,
              "srvr": parse_srvr,
              "reg_name": parse_reg_name,
              "query": parse_query,
              "SIP_Version": parse_SIP_Version,
              "INVITEm": parse_INVITEm,
              "ACKm": parse_ACKm,
              "OPTIONSm": parse_OPTIONSm,
              "BYEm": parse_BYEm,
              "CANCELm": parse_CANCELm,
              "REGISTERm": parse_REGISTERm,
              "SUBSCRIBEm": parse_SUBSCRIBEm,
              "NOTIFYm": parse_NOTIFYm,
              "REFERm": parse_REFERm,
              "Method": parse_Method,
              "Status_Line": parse_Status_Line,
              "Status_Code": parse_Status_Code,
              "extension_code": parse_extension_code,
              "Reason_Phrase": parse_Reason_Phrase,
              "Allow_Events": parse_Allow_Events,
              "Call_ID": parse_Call_ID,
              "Contact": parse_Contact,
              "contact_param": parse_contact_param,
              "name_addr": parse_name_addr,
              "display_name": parse_display_name,
              "contact_params": parse_contact_params,
              "c_p_q": parse_c_p_q,
              "c_p_expires": parse_c_p_expires,
              "delta_seconds": parse_delta_seconds,
              "qvalue": parse_qvalue,
              "generic_param": parse_generic_param,
              "gen_value": parse_gen_value,
              "Content_Disposition": parse_Content_Disposition,
              "disp_type": parse_disp_type,
              "disp_param": parse_disp_param,
              "handling_param": parse_handling_param,
              "Content_Encoding": parse_Content_Encoding,
              "Content_Length": parse_Content_Length,
              "Content_Type": parse_Content_Type,
              "media_type": parse_media_type,
              "m_type": parse_m_type,
              "discrete_type": parse_discrete_type,
              "composite_type": parse_composite_type,
              "extension_token": parse_extension_token,
              "x_token": parse_x_token,
              "m_subtype": parse_m_subtype,
              "m_parameter": parse_m_parameter,
              "m_value": parse_m_value,
              "CSeq": parse_CSeq,
              "CSeq_value": parse_CSeq_value,
              "Expires": parse_Expires,
              "Event": parse_Event,
              "event_type": parse_event_type,
              "From": parse_From,
              "from_param": parse_from_param,
              "tag_param": parse_tag_param,
              "Max_Forwards": parse_Max_Forwards,
              "Min_Expires": parse_Min_Expires,
              "Name_Addr_Header": parse_Name_Addr_Header,
              "Proxy_Authenticate": parse_Proxy_Authenticate,
              "challenge": parse_challenge,
              "other_challenge": parse_other_challenge,
              "auth_param": parse_auth_param,
              "digest_cln": parse_digest_cln,
              "realm": parse_realm,
              "realm_value": parse_realm_value,
              "domain": parse_domain,
              "URI": parse_URI,
              "nonce": parse_nonce,
              "nonce_value": parse_nonce_value,
              "opaque": parse_opaque,
              "stale": parse_stale,
              "algorithm": parse_algorithm,
              "qop_options": parse_qop_options,
              "qop_value": parse_qop_value,
              "Proxy_Require": parse_Proxy_Require,
              "Record_Route": parse_Record_Route,
              "rec_route": parse_rec_route,
              "Reason": parse_Reason,
              "reason_param": parse_reason_param,
              "reason_cause": parse_reason_cause,
              "Require": parse_Require,
              "Route": parse_Route,
              "route_param": parse_route_param,
              "Subscription_State": parse_Subscription_State,
              "substate_value": parse_substate_value,
              "subexp_params": parse_subexp_params,
              "event_reason_value": parse_event_reason_value,
              "Subject": parse_Subject,
              "Supported": parse_Supported,
              "To": parse_To,
              "to_param": parse_to_param,
              "Via": parse_Via,
              "via_param": parse_via_param,
              "via_params": parse_via_params,
              "via_ttl": parse_via_ttl,
              "via_maddr": parse_via_maddr,
              "via_received": parse_via_received,
              "via_branch": parse_via_branch,
              "response_port": parse_response_port,
              "rport": parse_rport,
              "sent_protocol": parse_sent_protocol,
              "protocol_name": parse_protocol_name,
              "transport": parse_transport,
              "sent_by": parse_sent_by,
              "via_host": parse_via_host,
              "via_port": parse_via_port,
              "ttl": parse_ttl,
              "WWW_Authenticate": parse_WWW_Authenticate,
              "Session_Expires": parse_Session_Expires,
              "s_e_expires": parse_s_e_expires,
              "s_e_params": parse_s_e_params,
              "s_e_refresher": parse_s_e_refresher,
              "extension_header": parse_extension_header,
              "header_value": parse_header_value,
              "message_body": parse_message_body,
              "uuid_URI": parse_uuid_URI,
              "uuid": parse_uuid,
              "hex4": parse_hex4,
              "hex8": parse_hex8,
              "hex12": parse_hex12,
              "Refer_To": parse_Refer_To,
              "Replaces": parse_Replaces,
              "call_id": parse_call_id,
              "replaces_param": parse_replaces_param,
              "to_tag": parse_to_tag,
              "from_tag": parse_from_tag,
              "early_flag": parse_early_flag
            };
            if (startRule !== void 0) {
              if (parseFunctions[startRule] === void 0) {
                throw new Error("Invalid rule name: " + quote(startRule) + ".");
              }
            } else {
              startRule = "CRLF";
            }
            var pos = 0;
            var reportFailures = 0;
            var rightmostFailuresPos = 0;
            var rightmostFailuresExpected = [];
            function padLeft(input2, padding, length) {
              var result3 = input2;
              var padLength = length - input2.length;
              for (var i = 0; i < padLength; i++) {
                result3 = padding + result3;
              }
              return result3;
            }
            function escape2(ch) {
              var charCode = ch.charCodeAt(0);
              var escapeChar;
              var length;
              if (charCode <= 255) {
                escapeChar = "x";
                length = 2;
              } else {
                escapeChar = "u";
                length = 4;
              }
              return "\\" + escapeChar + padLeft(charCode.toString(16).toUpperCase(), "0", length);
            }
            function matchFailed(failure) {
              if (pos < rightmostFailuresPos) {
                return;
              }
              if (pos > rightmostFailuresPos) {
                rightmostFailuresPos = pos;
                rightmostFailuresExpected = [];
              }
              rightmostFailuresExpected.push(failure);
            }
            function parse_CRLF() {
              var result0;
              if (input.substr(pos, 2) === "\r\n") {
                result0 = "\r\n";
                pos += 2;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"\\r\\n"');
                }
              }
              return result0;
            }
            function parse_DIGIT() {
              var result0;
              if (/^[0-9]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[0-9]");
                }
              }
              return result0;
            }
            function parse_ALPHA() {
              var result0;
              if (/^[a-zA-Z]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[a-zA-Z]");
                }
              }
              return result0;
            }
            function parse_HEXDIG() {
              var result0;
              if (/^[0-9a-fA-F]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[0-9a-fA-F]");
                }
              }
              return result0;
            }
            function parse_WSP() {
              var result0;
              result0 = parse_SP();
              if (result0 === null) {
                result0 = parse_HTAB();
              }
              return result0;
            }
            function parse_OCTET() {
              var result0;
              if (/^[\0-\xFF]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[\\0-\\xFF]");
                }
              }
              return result0;
            }
            function parse_DQUOTE() {
              var result0;
              if (/^["]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('["]');
                }
              }
              return result0;
            }
            function parse_SP() {
              var result0;
              if (input.charCodeAt(pos) === 32) {
                result0 = " ";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('" "');
                }
              }
              return result0;
            }
            function parse_HTAB() {
              var result0;
              if (input.charCodeAt(pos) === 9) {
                result0 = "	";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"\\t"');
                }
              }
              return result0;
            }
            function parse_alphanum() {
              var result0;
              if (/^[a-zA-Z0-9]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[a-zA-Z0-9]");
                }
              }
              return result0;
            }
            function parse_reserved() {
              var result0;
              if (input.charCodeAt(pos) === 59) {
                result0 = ";";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('";"');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 47) {
                  result0 = "/";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"/"');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 63) {
                    result0 = "?";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"?"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 58) {
                      result0 = ":";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('":"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 64) {
                        result0 = "@";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"@"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 38) {
                          result0 = "&";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"&"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 61) {
                            result0 = "=";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"="');
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 43) {
                              result0 = "+";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"+"');
                              }
                            }
                            if (result0 === null) {
                              if (input.charCodeAt(pos) === 36) {
                                result0 = "$";
                                pos++;
                              } else {
                                result0 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"$"');
                                }
                              }
                              if (result0 === null) {
                                if (input.charCodeAt(pos) === 44) {
                                  result0 = ",";
                                  pos++;
                                } else {
                                  result0 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('","');
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_unreserved() {
              var result0;
              result0 = parse_alphanum();
              if (result0 === null) {
                result0 = parse_mark();
              }
              return result0;
            }
            function parse_mark() {
              var result0;
              if (input.charCodeAt(pos) === 45) {
                result0 = "-";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"-"');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 95) {
                  result0 = "_";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"_"');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 46) {
                    result0 = ".";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 33) {
                      result0 = "!";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"!"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 126) {
                        result0 = "~";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"~"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 42) {
                          result0 = "*";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"*"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 39) {
                            result0 = "'";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed(`"'"`);
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 40) {
                              result0 = "(";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"("');
                              }
                            }
                            if (result0 === null) {
                              if (input.charCodeAt(pos) === 41) {
                                result0 = ")";
                                pos++;
                              } else {
                                result0 = null;
                                if (reportFailures === 0) {
                                  matchFailed('")"');
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_escaped() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.charCodeAt(pos) === 37) {
                result0 = "%";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"%"');
                }
              }
              if (result0 !== null) {
                result1 = parse_HEXDIG();
                if (result1 !== null) {
                  result22 = parse_HEXDIG();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, escaped) {
                  return escaped.join("");
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_LWS() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              pos2 = pos;
              result0 = [];
              result1 = parse_WSP();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_WSP();
              }
              if (result0 !== null) {
                result1 = parse_CRLF();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos2;
                }
              } else {
                result0 = null;
                pos = pos2;
              }
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result22 = parse_WSP();
                if (result22 !== null) {
                  result1 = [];
                  while (result22 !== null) {
                    result1.push(result22);
                    result22 = parse_WSP();
                  }
                } else {
                  result1 = null;
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return " ";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_SWS() {
              var result0;
              result0 = parse_LWS();
              result0 = result0 !== null ? result0 : "";
              return result0;
            }
            function parse_HCOLON() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = [];
              result1 = parse_SP();
              if (result1 === null) {
                result1 = parse_HTAB();
              }
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_SP();
                if (result1 === null) {
                  result1 = parse_HTAB();
                }
              }
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ":";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_TEXT_UTF8_TRIM() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result1 = parse_TEXT_UTF8char();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_TEXT_UTF8char();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = [];
                result3 = parse_LWS();
                while (result3 !== null) {
                  result22.push(result3);
                  result3 = parse_LWS();
                }
                if (result22 !== null) {
                  result3 = parse_TEXT_UTF8char();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = [];
                  result3 = parse_LWS();
                  while (result3 !== null) {
                    result22.push(result3);
                    result3 = parse_LWS();
                  }
                  if (result22 !== null) {
                    result3 = parse_TEXT_UTF8char();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_TEXT_UTF8char() {
              var result0;
              if (/^[!-~]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[!-~]");
                }
              }
              if (result0 === null) {
                result0 = parse_UTF8_NONASCII();
              }
              return result0;
            }
            function parse_UTF8_NONASCII() {
              var result0;
              if (/^[\x80-\uFFFF]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[\\x80-\\uFFFF]");
                }
              }
              return result0;
            }
            function parse_UTF8_CONT() {
              var result0;
              if (/^[\x80-\xBF]/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[\\x80-\\xBF]");
                }
              }
              return result0;
            }
            function parse_LHEX() {
              var result0;
              result0 = parse_DIGIT();
              if (result0 === null) {
                if (/^[a-f]/.test(input.charAt(pos))) {
                  result0 = input.charAt(pos);
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed("[a-f]");
                  }
                }
              }
              return result0;
            }
            function parse_token() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_alphanum();
              if (result1 === null) {
                if (input.charCodeAt(pos) === 45) {
                  result1 = "-";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"-"');
                  }
                }
                if (result1 === null) {
                  if (input.charCodeAt(pos) === 46) {
                    result1 = ".";
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 33) {
                      result1 = "!";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"!"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 37) {
                        result1 = "%";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"%"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 42) {
                          result1 = "*";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"*"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 95) {
                            result1 = "_";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"_"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 43) {
                              result1 = "+";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"+"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 96) {
                                result1 = "`";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"`"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 39) {
                                  result1 = "'";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed(`"'"`);
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 126) {
                                    result1 = "~";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"~"');
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_alphanum();
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 45) {
                      result1 = "-";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 46) {
                        result1 = ".";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"."');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 33) {
                          result1 = "!";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"!"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 37) {
                            result1 = "%";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"%"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 42) {
                              result1 = "*";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"*"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 95) {
                                result1 = "_";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"_"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 43) {
                                  result1 = "+";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"+"');
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 96) {
                                    result1 = "`";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"`"');
                                    }
                                  }
                                  if (result1 === null) {
                                    if (input.charCodeAt(pos) === 39) {
                                      result1 = "'";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed(`"'"`);
                                      }
                                    }
                                    if (result1 === null) {
                                      if (input.charCodeAt(pos) === 126) {
                                        result1 = "~";
                                        pos++;
                                      } else {
                                        result1 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('"~"');
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_token_nodot() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_alphanum();
              if (result1 === null) {
                if (input.charCodeAt(pos) === 45) {
                  result1 = "-";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"-"');
                  }
                }
                if (result1 === null) {
                  if (input.charCodeAt(pos) === 33) {
                    result1 = "!";
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"!"');
                    }
                  }
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 37) {
                      result1 = "%";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"%"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 42) {
                        result1 = "*";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"*"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 95) {
                          result1 = "_";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"_"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 43) {
                            result1 = "+";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"+"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 96) {
                              result1 = "`";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"`"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 39) {
                                result1 = "'";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed(`"'"`);
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 126) {
                                  result1 = "~";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"~"');
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_alphanum();
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 45) {
                      result1 = "-";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 33) {
                        result1 = "!";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"!"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 37) {
                          result1 = "%";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"%"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 42) {
                            result1 = "*";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"*"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 95) {
                              result1 = "_";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"_"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 43) {
                                result1 = "+";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"+"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 96) {
                                  result1 = "`";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"`"');
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 39) {
                                    result1 = "'";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed(`"'"`);
                                    }
                                  }
                                  if (result1 === null) {
                                    if (input.charCodeAt(pos) === 126) {
                                      result1 = "~";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('"~"');
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_separators() {
              var result0;
              if (input.charCodeAt(pos) === 40) {
                result0 = "(";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"("');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 41) {
                  result0 = ")";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('")"');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 60) {
                    result0 = "<";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"<"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 62) {
                      result0 = ">";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('">"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 64) {
                        result0 = "@";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"@"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 44) {
                          result0 = ",";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('","');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 59) {
                            result0 = ";";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('";"');
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 58) {
                              result0 = ":";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result0 === null) {
                              if (input.charCodeAt(pos) === 92) {
                                result0 = "\\";
                                pos++;
                              } else {
                                result0 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"\\\\"');
                                }
                              }
                              if (result0 === null) {
                                result0 = parse_DQUOTE();
                                if (result0 === null) {
                                  if (input.charCodeAt(pos) === 47) {
                                    result0 = "/";
                                    pos++;
                                  } else {
                                    result0 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"/"');
                                    }
                                  }
                                  if (result0 === null) {
                                    if (input.charCodeAt(pos) === 91) {
                                      result0 = "[";
                                      pos++;
                                    } else {
                                      result0 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('"["');
                                      }
                                    }
                                    if (result0 === null) {
                                      if (input.charCodeAt(pos) === 93) {
                                        result0 = "]";
                                        pos++;
                                      } else {
                                        result0 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('"]"');
                                        }
                                      }
                                      if (result0 === null) {
                                        if (input.charCodeAt(pos) === 63) {
                                          result0 = "?";
                                          pos++;
                                        } else {
                                          result0 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('"?"');
                                          }
                                        }
                                        if (result0 === null) {
                                          if (input.charCodeAt(pos) === 61) {
                                            result0 = "=";
                                            pos++;
                                          } else {
                                            result0 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('"="');
                                            }
                                          }
                                          if (result0 === null) {
                                            if (input.charCodeAt(pos) === 123) {
                                              result0 = "{";
                                              pos++;
                                            } else {
                                              result0 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('"{"');
                                              }
                                            }
                                            if (result0 === null) {
                                              if (input.charCodeAt(pos) === 125) {
                                                result0 = "}";
                                                pos++;
                                              } else {
                                                result0 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('"}"');
                                                }
                                              }
                                              if (result0 === null) {
                                                result0 = parse_SP();
                                                if (result0 === null) {
                                                  result0 = parse_HTAB();
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_word() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_alphanum();
              if (result1 === null) {
                if (input.charCodeAt(pos) === 45) {
                  result1 = "-";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"-"');
                  }
                }
                if (result1 === null) {
                  if (input.charCodeAt(pos) === 46) {
                    result1 = ".";
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 33) {
                      result1 = "!";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"!"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 37) {
                        result1 = "%";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"%"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 42) {
                          result1 = "*";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"*"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 95) {
                            result1 = "_";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"_"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 43) {
                              result1 = "+";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"+"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 96) {
                                result1 = "`";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"`"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 39) {
                                  result1 = "'";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed(`"'"`);
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 126) {
                                    result1 = "~";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"~"');
                                    }
                                  }
                                  if (result1 === null) {
                                    if (input.charCodeAt(pos) === 40) {
                                      result1 = "(";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('"("');
                                      }
                                    }
                                    if (result1 === null) {
                                      if (input.charCodeAt(pos) === 41) {
                                        result1 = ")";
                                        pos++;
                                      } else {
                                        result1 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('")"');
                                        }
                                      }
                                      if (result1 === null) {
                                        if (input.charCodeAt(pos) === 60) {
                                          result1 = "<";
                                          pos++;
                                        } else {
                                          result1 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('"<"');
                                          }
                                        }
                                        if (result1 === null) {
                                          if (input.charCodeAt(pos) === 62) {
                                            result1 = ">";
                                            pos++;
                                          } else {
                                            result1 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('">"');
                                            }
                                          }
                                          if (result1 === null) {
                                            if (input.charCodeAt(pos) === 58) {
                                              result1 = ":";
                                              pos++;
                                            } else {
                                              result1 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result1 === null) {
                                              if (input.charCodeAt(pos) === 92) {
                                                result1 = "\\";
                                                pos++;
                                              } else {
                                                result1 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('"\\\\"');
                                                }
                                              }
                                              if (result1 === null) {
                                                result1 = parse_DQUOTE();
                                                if (result1 === null) {
                                                  if (input.charCodeAt(pos) === 47) {
                                                    result1 = "/";
                                                    pos++;
                                                  } else {
                                                    result1 = null;
                                                    if (reportFailures === 0) {
                                                      matchFailed('"/"');
                                                    }
                                                  }
                                                  if (result1 === null) {
                                                    if (input.charCodeAt(pos) === 91) {
                                                      result1 = "[";
                                                      pos++;
                                                    } else {
                                                      result1 = null;
                                                      if (reportFailures === 0) {
                                                        matchFailed('"["');
                                                      }
                                                    }
                                                    if (result1 === null) {
                                                      if (input.charCodeAt(pos) === 93) {
                                                        result1 = "]";
                                                        pos++;
                                                      } else {
                                                        result1 = null;
                                                        if (reportFailures === 0) {
                                                          matchFailed('"]"');
                                                        }
                                                      }
                                                      if (result1 === null) {
                                                        if (input.charCodeAt(pos) === 63) {
                                                          result1 = "?";
                                                          pos++;
                                                        } else {
                                                          result1 = null;
                                                          if (reportFailures === 0) {
                                                            matchFailed('"?"');
                                                          }
                                                        }
                                                        if (result1 === null) {
                                                          if (input.charCodeAt(pos) === 123) {
                                                            result1 = "{";
                                                            pos++;
                                                          } else {
                                                            result1 = null;
                                                            if (reportFailures === 0) {
                                                              matchFailed('"{"');
                                                            }
                                                          }
                                                          if (result1 === null) {
                                                            if (input.charCodeAt(pos) === 125) {
                                                              result1 = "}";
                                                              pos++;
                                                            } else {
                                                              result1 = null;
                                                              if (reportFailures === 0) {
                                                                matchFailed('"}"');
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_alphanum();
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 45) {
                      result1 = "-";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 46) {
                        result1 = ".";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"."');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 33) {
                          result1 = "!";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"!"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 37) {
                            result1 = "%";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"%"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 42) {
                              result1 = "*";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"*"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 95) {
                                result1 = "_";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"_"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 43) {
                                  result1 = "+";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"+"');
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 96) {
                                    result1 = "`";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"`"');
                                    }
                                  }
                                  if (result1 === null) {
                                    if (input.charCodeAt(pos) === 39) {
                                      result1 = "'";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed(`"'"`);
                                      }
                                    }
                                    if (result1 === null) {
                                      if (input.charCodeAt(pos) === 126) {
                                        result1 = "~";
                                        pos++;
                                      } else {
                                        result1 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('"~"');
                                        }
                                      }
                                      if (result1 === null) {
                                        if (input.charCodeAt(pos) === 40) {
                                          result1 = "(";
                                          pos++;
                                        } else {
                                          result1 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('"("');
                                          }
                                        }
                                        if (result1 === null) {
                                          if (input.charCodeAt(pos) === 41) {
                                            result1 = ")";
                                            pos++;
                                          } else {
                                            result1 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('")"');
                                            }
                                          }
                                          if (result1 === null) {
                                            if (input.charCodeAt(pos) === 60) {
                                              result1 = "<";
                                              pos++;
                                            } else {
                                              result1 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('"<"');
                                              }
                                            }
                                            if (result1 === null) {
                                              if (input.charCodeAt(pos) === 62) {
                                                result1 = ">";
                                                pos++;
                                              } else {
                                                result1 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('">"');
                                                }
                                              }
                                              if (result1 === null) {
                                                if (input.charCodeAt(pos) === 58) {
                                                  result1 = ":";
                                                  pos++;
                                                } else {
                                                  result1 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result1 === null) {
                                                  if (input.charCodeAt(pos) === 92) {
                                                    result1 = "\\";
                                                    pos++;
                                                  } else {
                                                    result1 = null;
                                                    if (reportFailures === 0) {
                                                      matchFailed('"\\\\"');
                                                    }
                                                  }
                                                  if (result1 === null) {
                                                    result1 = parse_DQUOTE();
                                                    if (result1 === null) {
                                                      if (input.charCodeAt(pos) === 47) {
                                                        result1 = "/";
                                                        pos++;
                                                      } else {
                                                        result1 = null;
                                                        if (reportFailures === 0) {
                                                          matchFailed('"/"');
                                                        }
                                                      }
                                                      if (result1 === null) {
                                                        if (input.charCodeAt(pos) === 91) {
                                                          result1 = "[";
                                                          pos++;
                                                        } else {
                                                          result1 = null;
                                                          if (reportFailures === 0) {
                                                            matchFailed('"["');
                                                          }
                                                        }
                                                        if (result1 === null) {
                                                          if (input.charCodeAt(pos) === 93) {
                                                            result1 = "]";
                                                            pos++;
                                                          } else {
                                                            result1 = null;
                                                            if (reportFailures === 0) {
                                                              matchFailed('"]"');
                                                            }
                                                          }
                                                          if (result1 === null) {
                                                            if (input.charCodeAt(pos) === 63) {
                                                              result1 = "?";
                                                              pos++;
                                                            } else {
                                                              result1 = null;
                                                              if (reportFailures === 0) {
                                                                matchFailed('"?"');
                                                              }
                                                            }
                                                            if (result1 === null) {
                                                              if (input.charCodeAt(pos) === 123) {
                                                                result1 = "{";
                                                                pos++;
                                                              } else {
                                                                result1 = null;
                                                                if (reportFailures === 0) {
                                                                  matchFailed('"{"');
                                                                }
                                                              }
                                                              if (result1 === null) {
                                                                if (input.charCodeAt(pos) === 125) {
                                                                  result1 = "}";
                                                                  pos++;
                                                                } else {
                                                                  result1 = null;
                                                                  if (reportFailures === 0) {
                                                                    matchFailed('"}"');
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_STAR() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 42) {
                  result1 = "*";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"*"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return "*";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_SLASH() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 47) {
                  result1 = "/";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"/"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return "/";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_EQUAL() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 61) {
                  result1 = "=";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"="');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return "=";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_LPAREN() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 40) {
                  result1 = "(";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"("');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return "(";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_RPAREN() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 41) {
                  result1 = ")";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('")"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ")";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_RAQUOT() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.charCodeAt(pos) === 62) {
                result0 = ">";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('">"');
                }
              }
              if (result0 !== null) {
                result1 = parse_SWS();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ">";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_LAQUOT() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 60) {
                  result1 = "<";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"<"');
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return "<";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_COMMA() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 44) {
                  result1 = ",";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('","');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ",";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_SEMI() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 59) {
                  result1 = ";";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('";"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ";";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_COLON() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_SWS();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return ":";
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_LDQUOT() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                result1 = parse_DQUOTE();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return '"';
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_RDQUOT() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_DQUOTE();
              if (result0 !== null) {
                result1 = parse_SWS();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = /* @__PURE__ */ function(offset2) {
                  return '"';
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_comment() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_LPAREN();
              if (result0 !== null) {
                result1 = [];
                result22 = parse_ctext();
                if (result22 === null) {
                  result22 = parse_quoted_pair();
                  if (result22 === null) {
                    result22 = parse_comment();
                  }
                }
                while (result22 !== null) {
                  result1.push(result22);
                  result22 = parse_ctext();
                  if (result22 === null) {
                    result22 = parse_quoted_pair();
                    if (result22 === null) {
                      result22 = parse_comment();
                    }
                  }
                }
                if (result1 !== null) {
                  result22 = parse_RPAREN();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_ctext() {
              var result0;
              if (/^[!-']/.test(input.charAt(pos))) {
                result0 = input.charAt(pos);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed("[!-']");
                }
              }
              if (result0 === null) {
                if (/^[*-[]/.test(input.charAt(pos))) {
                  result0 = input.charAt(pos);
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed("[*-[]");
                  }
                }
                if (result0 === null) {
                  if (/^[\]-~]/.test(input.charAt(pos))) {
                    result0 = input.charAt(pos);
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed("[\\]-~]");
                    }
                  }
                  if (result0 === null) {
                    result0 = parse_UTF8_NONASCII();
                    if (result0 === null) {
                      result0 = parse_LWS();
                    }
                  }
                }
              }
              return result0;
            }
            function parse_quoted_string() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                result1 = parse_DQUOTE();
                if (result1 !== null) {
                  result22 = [];
                  result3 = parse_qdtext();
                  if (result3 === null) {
                    result3 = parse_quoted_pair();
                  }
                  while (result3 !== null) {
                    result22.push(result3);
                    result3 = parse_qdtext();
                    if (result3 === null) {
                      result3 = parse_quoted_pair();
                    }
                  }
                  if (result22 !== null) {
                    result3 = parse_DQUOTE();
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_quoted_string_clean() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SWS();
              if (result0 !== null) {
                result1 = parse_DQUOTE();
                if (result1 !== null) {
                  result22 = [];
                  result3 = parse_qdtext();
                  if (result3 === null) {
                    result3 = parse_quoted_pair();
                  }
                  while (result3 !== null) {
                    result22.push(result3);
                    result3 = parse_qdtext();
                    if (result3 === null) {
                      result3 = parse_quoted_pair();
                    }
                  }
                  if (result22 !== null) {
                    result3 = parse_DQUOTE();
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var trimmed = input.substring(pos, offset2).trim();
                  return trimmed.substring(1, trimmed.length - 1).replace(/\\([\x00-\x09\x0b-\x0c\x0e-\x7f])/g, "$1");
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_qdtext() {
              var result0;
              result0 = parse_LWS();
              if (result0 === null) {
                if (input.charCodeAt(pos) === 33) {
                  result0 = "!";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"!"');
                  }
                }
                if (result0 === null) {
                  if (/^[#-[]/.test(input.charAt(pos))) {
                    result0 = input.charAt(pos);
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed("[#-[]");
                    }
                  }
                  if (result0 === null) {
                    if (/^[\]-~]/.test(input.charAt(pos))) {
                      result0 = input.charAt(pos);
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed("[\\]-~]");
                      }
                    }
                    if (result0 === null) {
                      result0 = parse_UTF8_NONASCII();
                    }
                  }
                }
              }
              return result0;
            }
            function parse_quoted_pair() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              if (input.charCodeAt(pos) === 92) {
                result0 = "\\";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"\\\\"');
                }
              }
              if (result0 !== null) {
                if (/^[\0-\t]/.test(input.charAt(pos))) {
                  result1 = input.charAt(pos);
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed("[\\0-\\t]");
                  }
                }
                if (result1 === null) {
                  if (/^[\x0B-\f]/.test(input.charAt(pos))) {
                    result1 = input.charAt(pos);
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed("[\\x0B-\\f]");
                    }
                  }
                  if (result1 === null) {
                    if (/^[\x0E-]/.test(input.charAt(pos))) {
                      result1 = input.charAt(pos);
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed("[\\x0E-\x7F]");
                      }
                    }
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_SIP_URI_noparams() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_uri_scheme();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_userinfo();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_hostport();
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  try {
                    data.uri = new URI(data.scheme, data.user, data.host, data.port);
                    delete data.scheme;
                    delete data.user;
                    delete data.host;
                    delete data.host_type;
                    delete data.port;
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_SIP_URI() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_uri_scheme();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_userinfo();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_hostport();
                    if (result3 !== null) {
                      result4 = parse_uri_parameters();
                      if (result4 !== null) {
                        result5 = parse_headers();
                        result5 = result5 !== null ? result5 : "";
                        if (result5 !== null) {
                          result0 = [result0, result1, result22, result3, result4, result5];
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var header;
                  try {
                    data.uri = new URI(data.scheme, data.user, data.host, data.port, data.uri_params, data.uri_headers);
                    delete data.scheme;
                    delete data.user;
                    delete data.host;
                    delete data.host_type;
                    delete data.port;
                    delete data.uri_params;
                    if (startRule === "SIP_URI") {
                      data = data.uri;
                    }
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_uri_scheme() {
              var result0;
              result0 = parse_uri_scheme_sips();
              if (result0 === null) {
                result0 = parse_uri_scheme_sip();
              }
              return result0;
            }
            function parse_uri_scheme_sips() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 4).toLowerCase() === "sips") {
                result0 = input.substr(pos, 4);
                pos += 4;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"sips"');
                }
              }
              if (result0 !== null) {
                result0 = function(offset2, scheme) {
                  data.scheme = scheme.toLowerCase();
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_uri_scheme_sip() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 3).toLowerCase() === "sip") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"sip"');
                }
              }
              if (result0 !== null) {
                result0 = function(offset2, scheme) {
                  data.scheme = scheme.toLowerCase();
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_userinfo() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_user();
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_password();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  if (input.charCodeAt(pos) === 64) {
                    result22 = "@";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"@"');
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.user = decodeURIComponent(input.substring(pos - 1, offset2));
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_user() {
              var result0, result1;
              result1 = parse_unreserved();
              if (result1 === null) {
                result1 = parse_escaped();
                if (result1 === null) {
                  result1 = parse_user_unreserved();
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_unreserved();
                  if (result1 === null) {
                    result1 = parse_escaped();
                    if (result1 === null) {
                      result1 = parse_user_unreserved();
                    }
                  }
                }
              } else {
                result0 = null;
              }
              return result0;
            }
            function parse_user_unreserved() {
              var result0;
              if (input.charCodeAt(pos) === 38) {
                result0 = "&";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"&"');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 61) {
                  result0 = "=";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"="');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 43) {
                    result0 = "+";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"+"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 36) {
                      result0 = "$";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"$"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 44) {
                        result0 = ",";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('","');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 59) {
                          result0 = ";";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('";"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 63) {
                            result0 = "?";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"?"');
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 47) {
                              result0 = "/";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"/"');
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_password() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result0 = [];
              result1 = parse_unreserved();
              if (result1 === null) {
                result1 = parse_escaped();
                if (result1 === null) {
                  if (input.charCodeAt(pos) === 38) {
                    result1 = "&";
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"&"');
                    }
                  }
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 61) {
                      result1 = "=";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"="');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 43) {
                        result1 = "+";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"+"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 36) {
                          result1 = "$";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"$"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 44) {
                            result1 = ",";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('","');
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_unreserved();
                if (result1 === null) {
                  result1 = parse_escaped();
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 38) {
                      result1 = "&";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"&"');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 61) {
                        result1 = "=";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"="');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 43) {
                          result1 = "+";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('"+"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 36) {
                            result1 = "$";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"$"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 44) {
                              result1 = ",";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('","');
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.password = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_hostport() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_host();
              if (result0 !== null) {
                pos1 = pos;
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_port();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos1;
                  }
                } else {
                  result1 = null;
                  pos = pos1;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_host() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_hostname();
              if (result0 === null) {
                result0 = parse_IPv4address();
                if (result0 === null) {
                  result0 = parse_IPv6reference();
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host = input.substring(pos, offset2).toLowerCase();
                  return data.host;
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_hostname() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = [];
              pos2 = pos;
              result1 = parse_domainlabel();
              if (result1 !== null) {
                if (input.charCodeAt(pos) === 46) {
                  result22 = ".";
                  pos++;
                } else {
                  result22 = null;
                  if (reportFailures === 0) {
                    matchFailed('"."');
                  }
                }
                if (result22 !== null) {
                  result1 = [result1, result22];
                } else {
                  result1 = null;
                  pos = pos2;
                }
              } else {
                result1 = null;
                pos = pos2;
              }
              while (result1 !== null) {
                result0.push(result1);
                pos2 = pos;
                result1 = parse_domainlabel();
                if (result1 !== null) {
                  if (input.charCodeAt(pos) === 46) {
                    result22 = ".";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
              }
              if (result0 !== null) {
                result1 = parse_toplabel();
                if (result1 !== null) {
                  if (input.charCodeAt(pos) === 46) {
                    result22 = ".";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host_type = "domain";
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_domainlabel() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_alphanum();
              if (result0 !== null) {
                result1 = [];
                result22 = parse_alphanum();
                if (result22 === null) {
                  if (input.charCodeAt(pos) === 45) {
                    result22 = "-";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"-"');
                    }
                  }
                  if (result22 === null) {
                    if (input.charCodeAt(pos) === 95) {
                      result22 = "_";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"_"');
                      }
                    }
                  }
                }
                while (result22 !== null) {
                  result1.push(result22);
                  result22 = parse_alphanum();
                  if (result22 === null) {
                    if (input.charCodeAt(pos) === 45) {
                      result22 = "-";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result22 === null) {
                      if (input.charCodeAt(pos) === 95) {
                        result22 = "_";
                        pos++;
                      } else {
                        result22 = null;
                        if (reportFailures === 0) {
                          matchFailed('"_"');
                        }
                      }
                    }
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_toplabel() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_ALPHA();
              if (result0 !== null) {
                result1 = [];
                result22 = parse_alphanum();
                if (result22 === null) {
                  if (input.charCodeAt(pos) === 45) {
                    result22 = "-";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"-"');
                    }
                  }
                  if (result22 === null) {
                    if (input.charCodeAt(pos) === 95) {
                      result22 = "_";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"_"');
                      }
                    }
                  }
                }
                while (result22 !== null) {
                  result1.push(result22);
                  result22 = parse_alphanum();
                  if (result22 === null) {
                    if (input.charCodeAt(pos) === 45) {
                      result22 = "-";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result22 === null) {
                      if (input.charCodeAt(pos) === 95) {
                        result22 = "_";
                        pos++;
                      } else {
                        result22 = null;
                        if (reportFailures === 0) {
                          matchFailed('"_"');
                        }
                      }
                    }
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_IPv6reference() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.charCodeAt(pos) === 91) {
                result0 = "[";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"["');
                }
              }
              if (result0 !== null) {
                result1 = parse_IPv6address();
                if (result1 !== null) {
                  if (input.charCodeAt(pos) === 93) {
                    result22 = "]";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"]"');
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host_type = "IPv6";
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_IPv6address() {
              var result0, result1, result22, result3, result4, result5, result6, result7, result8, result9, result10, result11, result12;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_h16();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_h16();
                  if (result22 !== null) {
                    if (input.charCodeAt(pos) === 58) {
                      result3 = ":";
                      pos++;
                    } else {
                      result3 = null;
                      if (reportFailures === 0) {
                        matchFailed('":"');
                      }
                    }
                    if (result3 !== null) {
                      result4 = parse_h16();
                      if (result4 !== null) {
                        if (input.charCodeAt(pos) === 58) {
                          result5 = ":";
                          pos++;
                        } else {
                          result5 = null;
                          if (reportFailures === 0) {
                            matchFailed('":"');
                          }
                        }
                        if (result5 !== null) {
                          result6 = parse_h16();
                          if (result6 !== null) {
                            if (input.charCodeAt(pos) === 58) {
                              result7 = ":";
                              pos++;
                            } else {
                              result7 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result7 !== null) {
                              result8 = parse_h16();
                              if (result8 !== null) {
                                if (input.charCodeAt(pos) === 58) {
                                  result9 = ":";
                                  pos++;
                                } else {
                                  result9 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('":"');
                                  }
                                }
                                if (result9 !== null) {
                                  result10 = parse_h16();
                                  if (result10 !== null) {
                                    if (input.charCodeAt(pos) === 58) {
                                      result11 = ":";
                                      pos++;
                                    } else {
                                      result11 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('":"');
                                      }
                                    }
                                    if (result11 !== null) {
                                      result12 = parse_ls32();
                                      if (result12 !== null) {
                                        result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8, result9, result10, result11, result12];
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 === null) {
                pos1 = pos;
                if (input.substr(pos, 2) === "::") {
                  result0 = "::";
                  pos += 2;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"::"');
                  }
                }
                if (result0 !== null) {
                  result1 = parse_h16();
                  if (result1 !== null) {
                    if (input.charCodeAt(pos) === 58) {
                      result22 = ":";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('":"');
                      }
                    }
                    if (result22 !== null) {
                      result3 = parse_h16();
                      if (result3 !== null) {
                        if (input.charCodeAt(pos) === 58) {
                          result4 = ":";
                          pos++;
                        } else {
                          result4 = null;
                          if (reportFailures === 0) {
                            matchFailed('":"');
                          }
                        }
                        if (result4 !== null) {
                          result5 = parse_h16();
                          if (result5 !== null) {
                            if (input.charCodeAt(pos) === 58) {
                              result6 = ":";
                              pos++;
                            } else {
                              result6 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result6 !== null) {
                              result7 = parse_h16();
                              if (result7 !== null) {
                                if (input.charCodeAt(pos) === 58) {
                                  result8 = ":";
                                  pos++;
                                } else {
                                  result8 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('":"');
                                  }
                                }
                                if (result8 !== null) {
                                  result9 = parse_h16();
                                  if (result9 !== null) {
                                    if (input.charCodeAt(pos) === 58) {
                                      result10 = ":";
                                      pos++;
                                    } else {
                                      result10 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('":"');
                                      }
                                    }
                                    if (result10 !== null) {
                                      result11 = parse_ls32();
                                      if (result11 !== null) {
                                        result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8, result9, result10, result11];
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
                if (result0 === null) {
                  pos1 = pos;
                  if (input.substr(pos, 2) === "::") {
                    result0 = "::";
                    pos += 2;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"::"');
                    }
                  }
                  if (result0 !== null) {
                    result1 = parse_h16();
                    if (result1 !== null) {
                      if (input.charCodeAt(pos) === 58) {
                        result22 = ":";
                        pos++;
                      } else {
                        result22 = null;
                        if (reportFailures === 0) {
                          matchFailed('":"');
                        }
                      }
                      if (result22 !== null) {
                        result3 = parse_h16();
                        if (result3 !== null) {
                          if (input.charCodeAt(pos) === 58) {
                            result4 = ":";
                            pos++;
                          } else {
                            result4 = null;
                            if (reportFailures === 0) {
                              matchFailed('":"');
                            }
                          }
                          if (result4 !== null) {
                            result5 = parse_h16();
                            if (result5 !== null) {
                              if (input.charCodeAt(pos) === 58) {
                                result6 = ":";
                                pos++;
                              } else {
                                result6 = null;
                                if (reportFailures === 0) {
                                  matchFailed('":"');
                                }
                              }
                              if (result6 !== null) {
                                result7 = parse_h16();
                                if (result7 !== null) {
                                  if (input.charCodeAt(pos) === 58) {
                                    result8 = ":";
                                    pos++;
                                  } else {
                                    result8 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('":"');
                                    }
                                  }
                                  if (result8 !== null) {
                                    result9 = parse_ls32();
                                    if (result9 !== null) {
                                      result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8, result9];
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                  if (result0 === null) {
                    pos1 = pos;
                    if (input.substr(pos, 2) === "::") {
                      result0 = "::";
                      pos += 2;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"::"');
                      }
                    }
                    if (result0 !== null) {
                      result1 = parse_h16();
                      if (result1 !== null) {
                        if (input.charCodeAt(pos) === 58) {
                          result22 = ":";
                          pos++;
                        } else {
                          result22 = null;
                          if (reportFailures === 0) {
                            matchFailed('":"');
                          }
                        }
                        if (result22 !== null) {
                          result3 = parse_h16();
                          if (result3 !== null) {
                            if (input.charCodeAt(pos) === 58) {
                              result4 = ":";
                              pos++;
                            } else {
                              result4 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result4 !== null) {
                              result5 = parse_h16();
                              if (result5 !== null) {
                                if (input.charCodeAt(pos) === 58) {
                                  result6 = ":";
                                  pos++;
                                } else {
                                  result6 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('":"');
                                  }
                                }
                                if (result6 !== null) {
                                  result7 = parse_ls32();
                                  if (result7 !== null) {
                                    result0 = [result0, result1, result22, result3, result4, result5, result6, result7];
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                    if (result0 === null) {
                      pos1 = pos;
                      if (input.substr(pos, 2) === "::") {
                        result0 = "::";
                        pos += 2;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"::"');
                        }
                      }
                      if (result0 !== null) {
                        result1 = parse_h16();
                        if (result1 !== null) {
                          if (input.charCodeAt(pos) === 58) {
                            result22 = ":";
                            pos++;
                          } else {
                            result22 = null;
                            if (reportFailures === 0) {
                              matchFailed('":"');
                            }
                          }
                          if (result22 !== null) {
                            result3 = parse_h16();
                            if (result3 !== null) {
                              if (input.charCodeAt(pos) === 58) {
                                result4 = ":";
                                pos++;
                              } else {
                                result4 = null;
                                if (reportFailures === 0) {
                                  matchFailed('":"');
                                }
                              }
                              if (result4 !== null) {
                                result5 = parse_ls32();
                                if (result5 !== null) {
                                  result0 = [result0, result1, result22, result3, result4, result5];
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                      if (result0 === null) {
                        pos1 = pos;
                        if (input.substr(pos, 2) === "::") {
                          result0 = "::";
                          pos += 2;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"::"');
                          }
                        }
                        if (result0 !== null) {
                          result1 = parse_h16();
                          if (result1 !== null) {
                            if (input.charCodeAt(pos) === 58) {
                              result22 = ":";
                              pos++;
                            } else {
                              result22 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result22 !== null) {
                              result3 = parse_ls32();
                              if (result3 !== null) {
                                result0 = [result0, result1, result22, result3];
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                        if (result0 === null) {
                          pos1 = pos;
                          if (input.substr(pos, 2) === "::") {
                            result0 = "::";
                            pos += 2;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"::"');
                            }
                          }
                          if (result0 !== null) {
                            result1 = parse_ls32();
                            if (result1 !== null) {
                              result0 = [result0, result1];
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                          if (result0 === null) {
                            pos1 = pos;
                            if (input.substr(pos, 2) === "::") {
                              result0 = "::";
                              pos += 2;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"::"');
                              }
                            }
                            if (result0 !== null) {
                              result1 = parse_h16();
                              if (result1 !== null) {
                                result0 = [result0, result1];
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                            if (result0 === null) {
                              pos1 = pos;
                              result0 = parse_h16();
                              if (result0 !== null) {
                                if (input.substr(pos, 2) === "::") {
                                  result1 = "::";
                                  pos += 2;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"::"');
                                  }
                                }
                                if (result1 !== null) {
                                  result22 = parse_h16();
                                  if (result22 !== null) {
                                    if (input.charCodeAt(pos) === 58) {
                                      result3 = ":";
                                      pos++;
                                    } else {
                                      result3 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('":"');
                                      }
                                    }
                                    if (result3 !== null) {
                                      result4 = parse_h16();
                                      if (result4 !== null) {
                                        if (input.charCodeAt(pos) === 58) {
                                          result5 = ":";
                                          pos++;
                                        } else {
                                          result5 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('":"');
                                          }
                                        }
                                        if (result5 !== null) {
                                          result6 = parse_h16();
                                          if (result6 !== null) {
                                            if (input.charCodeAt(pos) === 58) {
                                              result7 = ":";
                                              pos++;
                                            } else {
                                              result7 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result7 !== null) {
                                              result8 = parse_h16();
                                              if (result8 !== null) {
                                                if (input.charCodeAt(pos) === 58) {
                                                  result9 = ":";
                                                  pos++;
                                                } else {
                                                  result9 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result9 !== null) {
                                                  result10 = parse_ls32();
                                                  if (result10 !== null) {
                                                    result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8, result9, result10];
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                              if (result0 === null) {
                                pos1 = pos;
                                result0 = parse_h16();
                                if (result0 !== null) {
                                  pos2 = pos;
                                  if (input.charCodeAt(pos) === 58) {
                                    result1 = ":";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('":"');
                                    }
                                  }
                                  if (result1 !== null) {
                                    result22 = parse_h16();
                                    if (result22 !== null) {
                                      result1 = [result1, result22];
                                    } else {
                                      result1 = null;
                                      pos = pos2;
                                    }
                                  } else {
                                    result1 = null;
                                    pos = pos2;
                                  }
                                  result1 = result1 !== null ? result1 : "";
                                  if (result1 !== null) {
                                    if (input.substr(pos, 2) === "::") {
                                      result22 = "::";
                                      pos += 2;
                                    } else {
                                      result22 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('"::"');
                                      }
                                    }
                                    if (result22 !== null) {
                                      result3 = parse_h16();
                                      if (result3 !== null) {
                                        if (input.charCodeAt(pos) === 58) {
                                          result4 = ":";
                                          pos++;
                                        } else {
                                          result4 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('":"');
                                          }
                                        }
                                        if (result4 !== null) {
                                          result5 = parse_h16();
                                          if (result5 !== null) {
                                            if (input.charCodeAt(pos) === 58) {
                                              result6 = ":";
                                              pos++;
                                            } else {
                                              result6 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result6 !== null) {
                                              result7 = parse_h16();
                                              if (result7 !== null) {
                                                if (input.charCodeAt(pos) === 58) {
                                                  result8 = ":";
                                                  pos++;
                                                } else {
                                                  result8 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result8 !== null) {
                                                  result9 = parse_ls32();
                                                  if (result9 !== null) {
                                                    result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8, result9];
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                } else {
                                  result0 = null;
                                  pos = pos1;
                                }
                                if (result0 === null) {
                                  pos1 = pos;
                                  result0 = parse_h16();
                                  if (result0 !== null) {
                                    pos2 = pos;
                                    if (input.charCodeAt(pos) === 58) {
                                      result1 = ":";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('":"');
                                      }
                                    }
                                    if (result1 !== null) {
                                      result22 = parse_h16();
                                      if (result22 !== null) {
                                        result1 = [result1, result22];
                                      } else {
                                        result1 = null;
                                        pos = pos2;
                                      }
                                    } else {
                                      result1 = null;
                                      pos = pos2;
                                    }
                                    result1 = result1 !== null ? result1 : "";
                                    if (result1 !== null) {
                                      pos2 = pos;
                                      if (input.charCodeAt(pos) === 58) {
                                        result22 = ":";
                                        pos++;
                                      } else {
                                        result22 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('":"');
                                        }
                                      }
                                      if (result22 !== null) {
                                        result3 = parse_h16();
                                        if (result3 !== null) {
                                          result22 = [result22, result3];
                                        } else {
                                          result22 = null;
                                          pos = pos2;
                                        }
                                      } else {
                                        result22 = null;
                                        pos = pos2;
                                      }
                                      result22 = result22 !== null ? result22 : "";
                                      if (result22 !== null) {
                                        if (input.substr(pos, 2) === "::") {
                                          result3 = "::";
                                          pos += 2;
                                        } else {
                                          result3 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('"::"');
                                          }
                                        }
                                        if (result3 !== null) {
                                          result4 = parse_h16();
                                          if (result4 !== null) {
                                            if (input.charCodeAt(pos) === 58) {
                                              result5 = ":";
                                              pos++;
                                            } else {
                                              result5 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result5 !== null) {
                                              result6 = parse_h16();
                                              if (result6 !== null) {
                                                if (input.charCodeAt(pos) === 58) {
                                                  result7 = ":";
                                                  pos++;
                                                } else {
                                                  result7 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result7 !== null) {
                                                  result8 = parse_ls32();
                                                  if (result8 !== null) {
                                                    result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8];
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                  } else {
                                    result0 = null;
                                    pos = pos1;
                                  }
                                  if (result0 === null) {
                                    pos1 = pos;
                                    result0 = parse_h16();
                                    if (result0 !== null) {
                                      pos2 = pos;
                                      if (input.charCodeAt(pos) === 58) {
                                        result1 = ":";
                                        pos++;
                                      } else {
                                        result1 = null;
                                        if (reportFailures === 0) {
                                          matchFailed('":"');
                                        }
                                      }
                                      if (result1 !== null) {
                                        result22 = parse_h16();
                                        if (result22 !== null) {
                                          result1 = [result1, result22];
                                        } else {
                                          result1 = null;
                                          pos = pos2;
                                        }
                                      } else {
                                        result1 = null;
                                        pos = pos2;
                                      }
                                      result1 = result1 !== null ? result1 : "";
                                      if (result1 !== null) {
                                        pos2 = pos;
                                        if (input.charCodeAt(pos) === 58) {
                                          result22 = ":";
                                          pos++;
                                        } else {
                                          result22 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('":"');
                                          }
                                        }
                                        if (result22 !== null) {
                                          result3 = parse_h16();
                                          if (result3 !== null) {
                                            result22 = [result22, result3];
                                          } else {
                                            result22 = null;
                                            pos = pos2;
                                          }
                                        } else {
                                          result22 = null;
                                          pos = pos2;
                                        }
                                        result22 = result22 !== null ? result22 : "";
                                        if (result22 !== null) {
                                          pos2 = pos;
                                          if (input.charCodeAt(pos) === 58) {
                                            result3 = ":";
                                            pos++;
                                          } else {
                                            result3 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('":"');
                                            }
                                          }
                                          if (result3 !== null) {
                                            result4 = parse_h16();
                                            if (result4 !== null) {
                                              result3 = [result3, result4];
                                            } else {
                                              result3 = null;
                                              pos = pos2;
                                            }
                                          } else {
                                            result3 = null;
                                            pos = pos2;
                                          }
                                          result3 = result3 !== null ? result3 : "";
                                          if (result3 !== null) {
                                            if (input.substr(pos, 2) === "::") {
                                              result4 = "::";
                                              pos += 2;
                                            } else {
                                              result4 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('"::"');
                                              }
                                            }
                                            if (result4 !== null) {
                                              result5 = parse_h16();
                                              if (result5 !== null) {
                                                if (input.charCodeAt(pos) === 58) {
                                                  result6 = ":";
                                                  pos++;
                                                } else {
                                                  result6 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result6 !== null) {
                                                  result7 = parse_ls32();
                                                  if (result7 !== null) {
                                                    result0 = [result0, result1, result22, result3, result4, result5, result6, result7];
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                    } else {
                                      result0 = null;
                                      pos = pos1;
                                    }
                                    if (result0 === null) {
                                      pos1 = pos;
                                      result0 = parse_h16();
                                      if (result0 !== null) {
                                        pos2 = pos;
                                        if (input.charCodeAt(pos) === 58) {
                                          result1 = ":";
                                          pos++;
                                        } else {
                                          result1 = null;
                                          if (reportFailures === 0) {
                                            matchFailed('":"');
                                          }
                                        }
                                        if (result1 !== null) {
                                          result22 = parse_h16();
                                          if (result22 !== null) {
                                            result1 = [result1, result22];
                                          } else {
                                            result1 = null;
                                            pos = pos2;
                                          }
                                        } else {
                                          result1 = null;
                                          pos = pos2;
                                        }
                                        result1 = result1 !== null ? result1 : "";
                                        if (result1 !== null) {
                                          pos2 = pos;
                                          if (input.charCodeAt(pos) === 58) {
                                            result22 = ":";
                                            pos++;
                                          } else {
                                            result22 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('":"');
                                            }
                                          }
                                          if (result22 !== null) {
                                            result3 = parse_h16();
                                            if (result3 !== null) {
                                              result22 = [result22, result3];
                                            } else {
                                              result22 = null;
                                              pos = pos2;
                                            }
                                          } else {
                                            result22 = null;
                                            pos = pos2;
                                          }
                                          result22 = result22 !== null ? result22 : "";
                                          if (result22 !== null) {
                                            pos2 = pos;
                                            if (input.charCodeAt(pos) === 58) {
                                              result3 = ":";
                                              pos++;
                                            } else {
                                              result3 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result3 !== null) {
                                              result4 = parse_h16();
                                              if (result4 !== null) {
                                                result3 = [result3, result4];
                                              } else {
                                                result3 = null;
                                                pos = pos2;
                                              }
                                            } else {
                                              result3 = null;
                                              pos = pos2;
                                            }
                                            result3 = result3 !== null ? result3 : "";
                                            if (result3 !== null) {
                                              pos2 = pos;
                                              if (input.charCodeAt(pos) === 58) {
                                                result4 = ":";
                                                pos++;
                                              } else {
                                                result4 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('":"');
                                                }
                                              }
                                              if (result4 !== null) {
                                                result5 = parse_h16();
                                                if (result5 !== null) {
                                                  result4 = [result4, result5];
                                                } else {
                                                  result4 = null;
                                                  pos = pos2;
                                                }
                                              } else {
                                                result4 = null;
                                                pos = pos2;
                                              }
                                              result4 = result4 !== null ? result4 : "";
                                              if (result4 !== null) {
                                                if (input.substr(pos, 2) === "::") {
                                                  result5 = "::";
                                                  pos += 2;
                                                } else {
                                                  result5 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('"::"');
                                                  }
                                                }
                                                if (result5 !== null) {
                                                  result6 = parse_ls32();
                                                  if (result6 !== null) {
                                                    result0 = [result0, result1, result22, result3, result4, result5, result6];
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                      } else {
                                        result0 = null;
                                        pos = pos1;
                                      }
                                      if (result0 === null) {
                                        pos1 = pos;
                                        result0 = parse_h16();
                                        if (result0 !== null) {
                                          pos2 = pos;
                                          if (input.charCodeAt(pos) === 58) {
                                            result1 = ":";
                                            pos++;
                                          } else {
                                            result1 = null;
                                            if (reportFailures === 0) {
                                              matchFailed('":"');
                                            }
                                          }
                                          if (result1 !== null) {
                                            result22 = parse_h16();
                                            if (result22 !== null) {
                                              result1 = [result1, result22];
                                            } else {
                                              result1 = null;
                                              pos = pos2;
                                            }
                                          } else {
                                            result1 = null;
                                            pos = pos2;
                                          }
                                          result1 = result1 !== null ? result1 : "";
                                          if (result1 !== null) {
                                            pos2 = pos;
                                            if (input.charCodeAt(pos) === 58) {
                                              result22 = ":";
                                              pos++;
                                            } else {
                                              result22 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result22 !== null) {
                                              result3 = parse_h16();
                                              if (result3 !== null) {
                                                result22 = [result22, result3];
                                              } else {
                                                result22 = null;
                                                pos = pos2;
                                              }
                                            } else {
                                              result22 = null;
                                              pos = pos2;
                                            }
                                            result22 = result22 !== null ? result22 : "";
                                            if (result22 !== null) {
                                              pos2 = pos;
                                              if (input.charCodeAt(pos) === 58) {
                                                result3 = ":";
                                                pos++;
                                              } else {
                                                result3 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('":"');
                                                }
                                              }
                                              if (result3 !== null) {
                                                result4 = parse_h16();
                                                if (result4 !== null) {
                                                  result3 = [result3, result4];
                                                } else {
                                                  result3 = null;
                                                  pos = pos2;
                                                }
                                              } else {
                                                result3 = null;
                                                pos = pos2;
                                              }
                                              result3 = result3 !== null ? result3 : "";
                                              if (result3 !== null) {
                                                pos2 = pos;
                                                if (input.charCodeAt(pos) === 58) {
                                                  result4 = ":";
                                                  pos++;
                                                } else {
                                                  result4 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result4 !== null) {
                                                  result5 = parse_h16();
                                                  if (result5 !== null) {
                                                    result4 = [result4, result5];
                                                  } else {
                                                    result4 = null;
                                                    pos = pos2;
                                                  }
                                                } else {
                                                  result4 = null;
                                                  pos = pos2;
                                                }
                                                result4 = result4 !== null ? result4 : "";
                                                if (result4 !== null) {
                                                  pos2 = pos;
                                                  if (input.charCodeAt(pos) === 58) {
                                                    result5 = ":";
                                                    pos++;
                                                  } else {
                                                    result5 = null;
                                                    if (reportFailures === 0) {
                                                      matchFailed('":"');
                                                    }
                                                  }
                                                  if (result5 !== null) {
                                                    result6 = parse_h16();
                                                    if (result6 !== null) {
                                                      result5 = [result5, result6];
                                                    } else {
                                                      result5 = null;
                                                      pos = pos2;
                                                    }
                                                  } else {
                                                    result5 = null;
                                                    pos = pos2;
                                                  }
                                                  result5 = result5 !== null ? result5 : "";
                                                  if (result5 !== null) {
                                                    if (input.substr(pos, 2) === "::") {
                                                      result6 = "::";
                                                      pos += 2;
                                                    } else {
                                                      result6 = null;
                                                      if (reportFailures === 0) {
                                                        matchFailed('"::"');
                                                      }
                                                    }
                                                    if (result6 !== null) {
                                                      result7 = parse_h16();
                                                      if (result7 !== null) {
                                                        result0 = [result0, result1, result22, result3, result4, result5, result6, result7];
                                                      } else {
                                                        result0 = null;
                                                        pos = pos1;
                                                      }
                                                    } else {
                                                      result0 = null;
                                                      pos = pos1;
                                                    }
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        } else {
                                          result0 = null;
                                          pos = pos1;
                                        }
                                        if (result0 === null) {
                                          pos1 = pos;
                                          result0 = parse_h16();
                                          if (result0 !== null) {
                                            pos2 = pos;
                                            if (input.charCodeAt(pos) === 58) {
                                              result1 = ":";
                                              pos++;
                                            } else {
                                              result1 = null;
                                              if (reportFailures === 0) {
                                                matchFailed('":"');
                                              }
                                            }
                                            if (result1 !== null) {
                                              result22 = parse_h16();
                                              if (result22 !== null) {
                                                result1 = [result1, result22];
                                              } else {
                                                result1 = null;
                                                pos = pos2;
                                              }
                                            } else {
                                              result1 = null;
                                              pos = pos2;
                                            }
                                            result1 = result1 !== null ? result1 : "";
                                            if (result1 !== null) {
                                              pos2 = pos;
                                              if (input.charCodeAt(pos) === 58) {
                                                result22 = ":";
                                                pos++;
                                              } else {
                                                result22 = null;
                                                if (reportFailures === 0) {
                                                  matchFailed('":"');
                                                }
                                              }
                                              if (result22 !== null) {
                                                result3 = parse_h16();
                                                if (result3 !== null) {
                                                  result22 = [result22, result3];
                                                } else {
                                                  result22 = null;
                                                  pos = pos2;
                                                }
                                              } else {
                                                result22 = null;
                                                pos = pos2;
                                              }
                                              result22 = result22 !== null ? result22 : "";
                                              if (result22 !== null) {
                                                pos2 = pos;
                                                if (input.charCodeAt(pos) === 58) {
                                                  result3 = ":";
                                                  pos++;
                                                } else {
                                                  result3 = null;
                                                  if (reportFailures === 0) {
                                                    matchFailed('":"');
                                                  }
                                                }
                                                if (result3 !== null) {
                                                  result4 = parse_h16();
                                                  if (result4 !== null) {
                                                    result3 = [result3, result4];
                                                  } else {
                                                    result3 = null;
                                                    pos = pos2;
                                                  }
                                                } else {
                                                  result3 = null;
                                                  pos = pos2;
                                                }
                                                result3 = result3 !== null ? result3 : "";
                                                if (result3 !== null) {
                                                  pos2 = pos;
                                                  if (input.charCodeAt(pos) === 58) {
                                                    result4 = ":";
                                                    pos++;
                                                  } else {
                                                    result4 = null;
                                                    if (reportFailures === 0) {
                                                      matchFailed('":"');
                                                    }
                                                  }
                                                  if (result4 !== null) {
                                                    result5 = parse_h16();
                                                    if (result5 !== null) {
                                                      result4 = [result4, result5];
                                                    } else {
                                                      result4 = null;
                                                      pos = pos2;
                                                    }
                                                  } else {
                                                    result4 = null;
                                                    pos = pos2;
                                                  }
                                                  result4 = result4 !== null ? result4 : "";
                                                  if (result4 !== null) {
                                                    pos2 = pos;
                                                    if (input.charCodeAt(pos) === 58) {
                                                      result5 = ":";
                                                      pos++;
                                                    } else {
                                                      result5 = null;
                                                      if (reportFailures === 0) {
                                                        matchFailed('":"');
                                                      }
                                                    }
                                                    if (result5 !== null) {
                                                      result6 = parse_h16();
                                                      if (result6 !== null) {
                                                        result5 = [result5, result6];
                                                      } else {
                                                        result5 = null;
                                                        pos = pos2;
                                                      }
                                                    } else {
                                                      result5 = null;
                                                      pos = pos2;
                                                    }
                                                    result5 = result5 !== null ? result5 : "";
                                                    if (result5 !== null) {
                                                      pos2 = pos;
                                                      if (input.charCodeAt(pos) === 58) {
                                                        result6 = ":";
                                                        pos++;
                                                      } else {
                                                        result6 = null;
                                                        if (reportFailures === 0) {
                                                          matchFailed('":"');
                                                        }
                                                      }
                                                      if (result6 !== null) {
                                                        result7 = parse_h16();
                                                        if (result7 !== null) {
                                                          result6 = [result6, result7];
                                                        } else {
                                                          result6 = null;
                                                          pos = pos2;
                                                        }
                                                      } else {
                                                        result6 = null;
                                                        pos = pos2;
                                                      }
                                                      result6 = result6 !== null ? result6 : "";
                                                      if (result6 !== null) {
                                                        if (input.substr(pos, 2) === "::") {
                                                          result7 = "::";
                                                          pos += 2;
                                                        } else {
                                                          result7 = null;
                                                          if (reportFailures === 0) {
                                                            matchFailed('"::"');
                                                          }
                                                        }
                                                        if (result7 !== null) {
                                                          result0 = [result0, result1, result22, result3, result4, result5, result6, result7];
                                                        } else {
                                                          result0 = null;
                                                          pos = pos1;
                                                        }
                                                      } else {
                                                        result0 = null;
                                                        pos = pos1;
                                                      }
                                                    } else {
                                                      result0 = null;
                                                      pos = pos1;
                                                    }
                                                  } else {
                                                    result0 = null;
                                                    pos = pos1;
                                                  }
                                                } else {
                                                  result0 = null;
                                                  pos = pos1;
                                                }
                                              } else {
                                                result0 = null;
                                                pos = pos1;
                                              }
                                            } else {
                                              result0 = null;
                                              pos = pos1;
                                            }
                                          } else {
                                            result0 = null;
                                            pos = pos1;
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host_type = "IPv6";
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_h16() {
              var result0, result1, result22, result3;
              var pos0;
              pos0 = pos;
              result0 = parse_HEXDIG();
              if (result0 !== null) {
                result1 = parse_HEXDIG();
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result22 = parse_HEXDIG();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_HEXDIG();
                    result3 = result3 !== null ? result3 : "";
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_ls32() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_h16();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_h16();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              if (result0 === null) {
                result0 = parse_IPv4address();
              }
              return result0;
            }
            function parse_IPv4address() {
              var result0, result1, result22, result3, result4, result5, result6;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_dec_octet();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 46) {
                  result1 = ".";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"."');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_dec_octet();
                  if (result22 !== null) {
                    if (input.charCodeAt(pos) === 46) {
                      result3 = ".";
                      pos++;
                    } else {
                      result3 = null;
                      if (reportFailures === 0) {
                        matchFailed('"."');
                      }
                    }
                    if (result3 !== null) {
                      result4 = parse_dec_octet();
                      if (result4 !== null) {
                        if (input.charCodeAt(pos) === 46) {
                          result5 = ".";
                          pos++;
                        } else {
                          result5 = null;
                          if (reportFailures === 0) {
                            matchFailed('"."');
                          }
                        }
                        if (result5 !== null) {
                          result6 = parse_dec_octet();
                          if (result6 !== null) {
                            result0 = [result0, result1, result22, result3, result4, result5, result6];
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host_type = "IPv4";
                  return input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_dec_octet() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 2) === "25") {
                result0 = "25";
                pos += 2;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"25"');
                }
              }
              if (result0 !== null) {
                if (/^[0-5]/.test(input.charAt(pos))) {
                  result1 = input.charAt(pos);
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed("[0-5]");
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              if (result0 === null) {
                pos0 = pos;
                if (input.charCodeAt(pos) === 50) {
                  result0 = "2";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"2"');
                  }
                }
                if (result0 !== null) {
                  if (/^[0-4]/.test(input.charAt(pos))) {
                    result1 = input.charAt(pos);
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed("[0-4]");
                    }
                  }
                  if (result1 !== null) {
                    result22 = parse_DIGIT();
                    if (result22 !== null) {
                      result0 = [result0, result1, result22];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
                if (result0 === null) {
                  pos0 = pos;
                  if (input.charCodeAt(pos) === 49) {
                    result0 = "1";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"1"');
                    }
                  }
                  if (result0 !== null) {
                    result1 = parse_DIGIT();
                    if (result1 !== null) {
                      result22 = parse_DIGIT();
                      if (result22 !== null) {
                        result0 = [result0, result1, result22];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                  if (result0 === null) {
                    pos0 = pos;
                    if (/^[1-9]/.test(input.charAt(pos))) {
                      result0 = input.charAt(pos);
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed("[1-9]");
                      }
                    }
                    if (result0 !== null) {
                      result1 = parse_DIGIT();
                      if (result1 !== null) {
                        result0 = [result0, result1];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                    if (result0 === null) {
                      result0 = parse_DIGIT();
                    }
                  }
                }
              }
              return result0;
            }
            function parse_port() {
              var result0, result1, result22, result3, result4;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_DIGIT();
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result1 = parse_DIGIT();
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_DIGIT();
                    result3 = result3 !== null ? result3 : "";
                    if (result3 !== null) {
                      result4 = parse_DIGIT();
                      result4 = result4 !== null ? result4 : "";
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, port) {
                  port = parseInt(port.join(""));
                  data.port = port;
                  return port;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_uri_parameters() {
              var result0, result1, result22;
              var pos0;
              result0 = [];
              pos0 = pos;
              if (input.charCodeAt(pos) === 59) {
                result1 = ";";
                pos++;
              } else {
                result1 = null;
                if (reportFailures === 0) {
                  matchFailed('";"');
                }
              }
              if (result1 !== null) {
                result22 = parse_uri_parameter();
                if (result22 !== null) {
                  result1 = [result1, result22];
                } else {
                  result1 = null;
                  pos = pos0;
                }
              } else {
                result1 = null;
                pos = pos0;
              }
              while (result1 !== null) {
                result0.push(result1);
                pos0 = pos;
                if (input.charCodeAt(pos) === 59) {
                  result1 = ";";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('";"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_uri_parameter();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos0;
                  }
                } else {
                  result1 = null;
                  pos = pos0;
                }
              }
              return result0;
            }
            function parse_uri_parameter() {
              var result0;
              result0 = parse_transport_param();
              if (result0 === null) {
                result0 = parse_user_param();
                if (result0 === null) {
                  result0 = parse_method_param();
                  if (result0 === null) {
                    result0 = parse_ttl_param();
                    if (result0 === null) {
                      result0 = parse_maddr_param();
                      if (result0 === null) {
                        result0 = parse_lr_param();
                        if (result0 === null) {
                          result0 = parse_other_param();
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_transport_param() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 10).toLowerCase() === "transport=") {
                result0 = input.substr(pos, 10);
                pos += 10;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"transport="');
                }
              }
              if (result0 !== null) {
                if (input.substr(pos, 3).toLowerCase() === "udp") {
                  result1 = input.substr(pos, 3);
                  pos += 3;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"udp"');
                  }
                }
                if (result1 === null) {
                  if (input.substr(pos, 3).toLowerCase() === "tcp") {
                    result1 = input.substr(pos, 3);
                    pos += 3;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"tcp"');
                    }
                  }
                  if (result1 === null) {
                    if (input.substr(pos, 4).toLowerCase() === "sctp") {
                      result1 = input.substr(pos, 4);
                      pos += 4;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('"sctp"');
                      }
                    }
                    if (result1 === null) {
                      if (input.substr(pos, 3).toLowerCase() === "tls") {
                        result1 = input.substr(pos, 3);
                        pos += 3;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"tls"');
                        }
                      }
                      if (result1 === null) {
                        result1 = parse_token();
                      }
                    }
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, transport) {
                  if (!data.uri_params) data.uri_params = {};
                  data.uri_params["transport"] = transport.toLowerCase();
                }(pos0, result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_user_param() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 5).toLowerCase() === "user=") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"user="');
                }
              }
              if (result0 !== null) {
                if (input.substr(pos, 5).toLowerCase() === "phone") {
                  result1 = input.substr(pos, 5);
                  pos += 5;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"phone"');
                  }
                }
                if (result1 === null) {
                  if (input.substr(pos, 2).toLowerCase() === "ip") {
                    result1 = input.substr(pos, 2);
                    pos += 2;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"ip"');
                    }
                  }
                  if (result1 === null) {
                    result1 = parse_token();
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, user) {
                  if (!data.uri_params) data.uri_params = {};
                  data.uri_params["user"] = user.toLowerCase();
                }(pos0, result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_method_param() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 7).toLowerCase() === "method=") {
                result0 = input.substr(pos, 7);
                pos += 7;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"method="');
                }
              }
              if (result0 !== null) {
                result1 = parse_Method();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, method) {
                  if (!data.uri_params) data.uri_params = {};
                  data.uri_params["method"] = method;
                }(pos0, result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_ttl_param() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 4).toLowerCase() === "ttl=") {
                result0 = input.substr(pos, 4);
                pos += 4;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"ttl="');
                }
              }
              if (result0 !== null) {
                result1 = parse_ttl();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, ttl) {
                  if (!data.params) data.params = {};
                  data.params["ttl"] = ttl;
                }(pos0, result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_maddr_param() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 6).toLowerCase() === "maddr=") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"maddr="');
                }
              }
              if (result0 !== null) {
                result1 = parse_host();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, maddr) {
                  if (!data.uri_params) data.uri_params = {};
                  data.uri_params["maddr"] = maddr;
                }(pos0, result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_lr_param() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 2).toLowerCase() === "lr") {
                result0 = input.substr(pos, 2);
                pos += 2;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"lr"');
                }
              }
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 61) {
                  result1 = "=";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"="');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  if (!data.uri_params) data.uri_params = {};
                  data.uri_params["lr"] = void 0;
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_other_param() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_pname();
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 61) {
                  result1 = "=";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"="');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_pvalue();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, param, value) {
                  if (!data.uri_params) data.uri_params = {};
                  if (typeof value === "undefined") {
                    value = void 0;
                  } else {
                    value = value[1];
                  }
                  data.uri_params[param.toLowerCase()] = value;
                }(pos0, result0[0], result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_pname() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_paramchar();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_paramchar();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, pname) {
                  return pname.join("");
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_pvalue() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_paramchar();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_paramchar();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, pvalue) {
                  return pvalue.join("");
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_paramchar() {
              var result0;
              result0 = parse_param_unreserved();
              if (result0 === null) {
                result0 = parse_unreserved();
                if (result0 === null) {
                  result0 = parse_escaped();
                }
              }
              return result0;
            }
            function parse_param_unreserved() {
              var result0;
              if (input.charCodeAt(pos) === 91) {
                result0 = "[";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"["');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 93) {
                  result0 = "]";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"]"');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 47) {
                    result0 = "/";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"/"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 58) {
                      result0 = ":";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('":"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 38) {
                        result0 = "&";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"&"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 43) {
                          result0 = "+";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"+"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 36) {
                            result0 = "$";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"$"');
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_headers() {
              var result0, result1, result22, result3, result4;
              var pos0, pos1;
              pos0 = pos;
              if (input.charCodeAt(pos) === 63) {
                result0 = "?";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"?"');
                }
              }
              if (result0 !== null) {
                result1 = parse_header();
                if (result1 !== null) {
                  result22 = [];
                  pos1 = pos;
                  if (input.charCodeAt(pos) === 38) {
                    result3 = "&";
                    pos++;
                  } else {
                    result3 = null;
                    if (reportFailures === 0) {
                      matchFailed('"&"');
                    }
                  }
                  if (result3 !== null) {
                    result4 = parse_header();
                    if (result4 !== null) {
                      result3 = [result3, result4];
                    } else {
                      result3 = null;
                      pos = pos1;
                    }
                  } else {
                    result3 = null;
                    pos = pos1;
                  }
                  while (result3 !== null) {
                    result22.push(result3);
                    pos1 = pos;
                    if (input.charCodeAt(pos) === 38) {
                      result3 = "&";
                      pos++;
                    } else {
                      result3 = null;
                      if (reportFailures === 0) {
                        matchFailed('"&"');
                      }
                    }
                    if (result3 !== null) {
                      result4 = parse_header();
                      if (result4 !== null) {
                        result3 = [result3, result4];
                      } else {
                        result3 = null;
                        pos = pos1;
                      }
                    } else {
                      result3 = null;
                      pos = pos1;
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_header() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_hname();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 61) {
                  result1 = "=";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"="');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_hvalue();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, hname, hvalue) {
                  hname = hname.join("").toLowerCase();
                  hvalue = hvalue.join("");
                  if (!data.uri_headers) data.uri_headers = {};
                  if (!data.uri_headers[hname]) {
                    data.uri_headers[hname] = [hvalue];
                  } else {
                    data.uri_headers[hname].push(hvalue);
                  }
                }(pos0, result0[0], result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_hname() {
              var result0, result1;
              result1 = parse_hnv_unreserved();
              if (result1 === null) {
                result1 = parse_unreserved();
                if (result1 === null) {
                  result1 = parse_escaped();
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_hnv_unreserved();
                  if (result1 === null) {
                    result1 = parse_unreserved();
                    if (result1 === null) {
                      result1 = parse_escaped();
                    }
                  }
                }
              } else {
                result0 = null;
              }
              return result0;
            }
            function parse_hvalue() {
              var result0, result1;
              result0 = [];
              result1 = parse_hnv_unreserved();
              if (result1 === null) {
                result1 = parse_unreserved();
                if (result1 === null) {
                  result1 = parse_escaped();
                }
              }
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_hnv_unreserved();
                if (result1 === null) {
                  result1 = parse_unreserved();
                  if (result1 === null) {
                    result1 = parse_escaped();
                  }
                }
              }
              return result0;
            }
            function parse_hnv_unreserved() {
              var result0;
              if (input.charCodeAt(pos) === 91) {
                result0 = "[";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"["');
                }
              }
              if (result0 === null) {
                if (input.charCodeAt(pos) === 93) {
                  result0 = "]";
                  pos++;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"]"');
                  }
                }
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 47) {
                    result0 = "/";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"/"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 63) {
                      result0 = "?";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"?"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 58) {
                        result0 = ":";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('":"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 43) {
                          result0 = "+";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"+"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 36) {
                            result0 = "$";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"$"');
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_Request_Response() {
              var result0;
              result0 = parse_Status_Line();
              if (result0 === null) {
                result0 = parse_Request_Line();
              }
              return result0;
            }
            function parse_Request_Line() {
              var result0, result1, result22, result3, result4;
              var pos0;
              pos0 = pos;
              result0 = parse_Method();
              if (result0 !== null) {
                result1 = parse_SP();
                if (result1 !== null) {
                  result22 = parse_Request_URI();
                  if (result22 !== null) {
                    result3 = parse_SP();
                    if (result3 !== null) {
                      result4 = parse_SIP_Version();
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Request_URI() {
              var result0;
              result0 = parse_SIP_URI();
              if (result0 === null) {
                result0 = parse_absoluteURI();
              }
              return result0;
            }
            function parse_absoluteURI() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_scheme();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 58) {
                  result1 = ":";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('":"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_hier_part();
                  if (result22 === null) {
                    result22 = parse_opaque_part();
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_hier_part() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_net_path();
              if (result0 === null) {
                result0 = parse_abs_path();
              }
              if (result0 !== null) {
                pos1 = pos;
                if (input.charCodeAt(pos) === 63) {
                  result1 = "?";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"?"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_query();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos1;
                  }
                } else {
                  result1 = null;
                  pos = pos1;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_net_path() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 2) === "//") {
                result0 = "//";
                pos += 2;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"//"');
                }
              }
              if (result0 !== null) {
                result1 = parse_authority();
                if (result1 !== null) {
                  result22 = parse_abs_path();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_abs_path() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              if (input.charCodeAt(pos) === 47) {
                result0 = "/";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"/"');
                }
              }
              if (result0 !== null) {
                result1 = parse_path_segments();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_opaque_part() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_uric_no_slash();
              if (result0 !== null) {
                result1 = [];
                result22 = parse_uric();
                while (result22 !== null) {
                  result1.push(result22);
                  result22 = parse_uric();
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_uric() {
              var result0;
              result0 = parse_reserved();
              if (result0 === null) {
                result0 = parse_unreserved();
                if (result0 === null) {
                  result0 = parse_escaped();
                }
              }
              return result0;
            }
            function parse_uric_no_slash() {
              var result0;
              result0 = parse_unreserved();
              if (result0 === null) {
                result0 = parse_escaped();
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 59) {
                    result0 = ";";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('";"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 63) {
                      result0 = "?";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"?"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 58) {
                        result0 = ":";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('":"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 64) {
                          result0 = "@";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"@"');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 38) {
                            result0 = "&";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"&"');
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 61) {
                              result0 = "=";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"="');
                              }
                            }
                            if (result0 === null) {
                              if (input.charCodeAt(pos) === 43) {
                                result0 = "+";
                                pos++;
                              } else {
                                result0 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"+"');
                                }
                              }
                              if (result0 === null) {
                                if (input.charCodeAt(pos) === 36) {
                                  result0 = "$";
                                  pos++;
                                } else {
                                  result0 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"$"');
                                  }
                                }
                                if (result0 === null) {
                                  if (input.charCodeAt(pos) === 44) {
                                    result0 = ",";
                                    pos++;
                                  } else {
                                    result0 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('","');
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_path_segments() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_segment();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                if (input.charCodeAt(pos) === 47) {
                  result22 = "/";
                  pos++;
                } else {
                  result22 = null;
                  if (reportFailures === 0) {
                    matchFailed('"/"');
                  }
                }
                if (result22 !== null) {
                  result3 = parse_segment();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  if (input.charCodeAt(pos) === 47) {
                    result22 = "/";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"/"');
                    }
                  }
                  if (result22 !== null) {
                    result3 = parse_segment();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_segment() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = [];
              result1 = parse_pchar();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_pchar();
              }
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                if (input.charCodeAt(pos) === 59) {
                  result22 = ";";
                  pos++;
                } else {
                  result22 = null;
                  if (reportFailures === 0) {
                    matchFailed('";"');
                  }
                }
                if (result22 !== null) {
                  result3 = parse_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  if (input.charCodeAt(pos) === 59) {
                    result22 = ";";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('";"');
                    }
                  }
                  if (result22 !== null) {
                    result3 = parse_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_param() {
              var result0, result1;
              result0 = [];
              result1 = parse_pchar();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_pchar();
              }
              return result0;
            }
            function parse_pchar() {
              var result0;
              result0 = parse_unreserved();
              if (result0 === null) {
                result0 = parse_escaped();
                if (result0 === null) {
                  if (input.charCodeAt(pos) === 58) {
                    result0 = ":";
                    pos++;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('":"');
                    }
                  }
                  if (result0 === null) {
                    if (input.charCodeAt(pos) === 64) {
                      result0 = "@";
                      pos++;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"@"');
                      }
                    }
                    if (result0 === null) {
                      if (input.charCodeAt(pos) === 38) {
                        result0 = "&";
                        pos++;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"&"');
                        }
                      }
                      if (result0 === null) {
                        if (input.charCodeAt(pos) === 61) {
                          result0 = "=";
                          pos++;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"="');
                          }
                        }
                        if (result0 === null) {
                          if (input.charCodeAt(pos) === 43) {
                            result0 = "+";
                            pos++;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"+"');
                            }
                          }
                          if (result0 === null) {
                            if (input.charCodeAt(pos) === 36) {
                              result0 = "$";
                              pos++;
                            } else {
                              result0 = null;
                              if (reportFailures === 0) {
                                matchFailed('"$"');
                              }
                            }
                            if (result0 === null) {
                              if (input.charCodeAt(pos) === 44) {
                                result0 = ",";
                                pos++;
                              } else {
                                result0 = null;
                                if (reportFailures === 0) {
                                  matchFailed('","');
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_scheme() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_ALPHA();
              if (result0 !== null) {
                result1 = [];
                result22 = parse_ALPHA();
                if (result22 === null) {
                  result22 = parse_DIGIT();
                  if (result22 === null) {
                    if (input.charCodeAt(pos) === 43) {
                      result22 = "+";
                      pos++;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"+"');
                      }
                    }
                    if (result22 === null) {
                      if (input.charCodeAt(pos) === 45) {
                        result22 = "-";
                        pos++;
                      } else {
                        result22 = null;
                        if (reportFailures === 0) {
                          matchFailed('"-"');
                        }
                      }
                      if (result22 === null) {
                        if (input.charCodeAt(pos) === 46) {
                          result22 = ".";
                          pos++;
                        } else {
                          result22 = null;
                          if (reportFailures === 0) {
                            matchFailed('"."');
                          }
                        }
                      }
                    }
                  }
                }
                while (result22 !== null) {
                  result1.push(result22);
                  result22 = parse_ALPHA();
                  if (result22 === null) {
                    result22 = parse_DIGIT();
                    if (result22 === null) {
                      if (input.charCodeAt(pos) === 43) {
                        result22 = "+";
                        pos++;
                      } else {
                        result22 = null;
                        if (reportFailures === 0) {
                          matchFailed('"+"');
                        }
                      }
                      if (result22 === null) {
                        if (input.charCodeAt(pos) === 45) {
                          result22 = "-";
                          pos++;
                        } else {
                          result22 = null;
                          if (reportFailures === 0) {
                            matchFailed('"-"');
                          }
                        }
                        if (result22 === null) {
                          if (input.charCodeAt(pos) === 46) {
                            result22 = ".";
                            pos++;
                          } else {
                            result22 = null;
                            if (reportFailures === 0) {
                              matchFailed('"."');
                            }
                          }
                        }
                      }
                    }
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.scheme = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_authority() {
              var result0;
              result0 = parse_srvr();
              if (result0 === null) {
                result0 = parse_reg_name();
              }
              return result0;
            }
            function parse_srvr() {
              var result0, result1;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_userinfo();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 64) {
                  result1 = "@";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"@"');
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result1 = parse_hostport();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              result0 = result0 !== null ? result0 : "";
              return result0;
            }
            function parse_reg_name() {
              var result0, result1;
              result1 = parse_unreserved();
              if (result1 === null) {
                result1 = parse_escaped();
                if (result1 === null) {
                  if (input.charCodeAt(pos) === 36) {
                    result1 = "$";
                    pos++;
                  } else {
                    result1 = null;
                    if (reportFailures === 0) {
                      matchFailed('"$"');
                    }
                  }
                  if (result1 === null) {
                    if (input.charCodeAt(pos) === 44) {
                      result1 = ",";
                      pos++;
                    } else {
                      result1 = null;
                      if (reportFailures === 0) {
                        matchFailed('","');
                      }
                    }
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 59) {
                        result1 = ";";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('";"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 58) {
                          result1 = ":";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('":"');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 64) {
                            result1 = "@";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('"@"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 38) {
                              result1 = "&";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('"&"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 61) {
                                result1 = "=";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"="');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 43) {
                                  result1 = "+";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"+"');
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_unreserved();
                  if (result1 === null) {
                    result1 = parse_escaped();
                    if (result1 === null) {
                      if (input.charCodeAt(pos) === 36) {
                        result1 = "$";
                        pos++;
                      } else {
                        result1 = null;
                        if (reportFailures === 0) {
                          matchFailed('"$"');
                        }
                      }
                      if (result1 === null) {
                        if (input.charCodeAt(pos) === 44) {
                          result1 = ",";
                          pos++;
                        } else {
                          result1 = null;
                          if (reportFailures === 0) {
                            matchFailed('","');
                          }
                        }
                        if (result1 === null) {
                          if (input.charCodeAt(pos) === 59) {
                            result1 = ";";
                            pos++;
                          } else {
                            result1 = null;
                            if (reportFailures === 0) {
                              matchFailed('";"');
                            }
                          }
                          if (result1 === null) {
                            if (input.charCodeAt(pos) === 58) {
                              result1 = ":";
                              pos++;
                            } else {
                              result1 = null;
                              if (reportFailures === 0) {
                                matchFailed('":"');
                              }
                            }
                            if (result1 === null) {
                              if (input.charCodeAt(pos) === 64) {
                                result1 = "@";
                                pos++;
                              } else {
                                result1 = null;
                                if (reportFailures === 0) {
                                  matchFailed('"@"');
                                }
                              }
                              if (result1 === null) {
                                if (input.charCodeAt(pos) === 38) {
                                  result1 = "&";
                                  pos++;
                                } else {
                                  result1 = null;
                                  if (reportFailures === 0) {
                                    matchFailed('"&"');
                                  }
                                }
                                if (result1 === null) {
                                  if (input.charCodeAt(pos) === 61) {
                                    result1 = "=";
                                    pos++;
                                  } else {
                                    result1 = null;
                                    if (reportFailures === 0) {
                                      matchFailed('"="');
                                    }
                                  }
                                  if (result1 === null) {
                                    if (input.charCodeAt(pos) === 43) {
                                      result1 = "+";
                                      pos++;
                                    } else {
                                      result1 = null;
                                      if (reportFailures === 0) {
                                        matchFailed('"+"');
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                result0 = null;
              }
              return result0;
            }
            function parse_query() {
              var result0, result1;
              result0 = [];
              result1 = parse_uric();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_uric();
              }
              return result0;
            }
            function parse_SIP_Version() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 3).toLowerCase() === "sip") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"SIP"');
                }
              }
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 47) {
                  result1 = "/";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"/"');
                  }
                }
                if (result1 !== null) {
                  result3 = parse_DIGIT();
                  if (result3 !== null) {
                    result22 = [];
                    while (result3 !== null) {
                      result22.push(result3);
                      result3 = parse_DIGIT();
                    }
                  } else {
                    result22 = null;
                  }
                  if (result22 !== null) {
                    if (input.charCodeAt(pos) === 46) {
                      result3 = ".";
                      pos++;
                    } else {
                      result3 = null;
                      if (reportFailures === 0) {
                        matchFailed('"."');
                      }
                    }
                    if (result3 !== null) {
                      result5 = parse_DIGIT();
                      if (result5 !== null) {
                        result4 = [];
                        while (result5 !== null) {
                          result4.push(result5);
                          result5 = parse_DIGIT();
                        }
                      } else {
                        result4 = null;
                      }
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.sip_version = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_INVITEm() {
              var result0;
              if (input.substr(pos, 6) === "INVITE") {
                result0 = "INVITE";
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"INVITE"');
                }
              }
              return result0;
            }
            function parse_ACKm() {
              var result0;
              if (input.substr(pos, 3) === "ACK") {
                result0 = "ACK";
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"ACK"');
                }
              }
              return result0;
            }
            function parse_OPTIONSm() {
              var result0;
              if (input.substr(pos, 7) === "OPTIONS") {
                result0 = "OPTIONS";
                pos += 7;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"OPTIONS"');
                }
              }
              return result0;
            }
            function parse_BYEm() {
              var result0;
              if (input.substr(pos, 3) === "BYE") {
                result0 = "BYE";
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"BYE"');
                }
              }
              return result0;
            }
            function parse_CANCELm() {
              var result0;
              if (input.substr(pos, 6) === "CANCEL") {
                result0 = "CANCEL";
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"CANCEL"');
                }
              }
              return result0;
            }
            function parse_REGISTERm() {
              var result0;
              if (input.substr(pos, 8) === "REGISTER") {
                result0 = "REGISTER";
                pos += 8;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"REGISTER"');
                }
              }
              return result0;
            }
            function parse_SUBSCRIBEm() {
              var result0;
              if (input.substr(pos, 9) === "SUBSCRIBE") {
                result0 = "SUBSCRIBE";
                pos += 9;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"SUBSCRIBE"');
                }
              }
              return result0;
            }
            function parse_NOTIFYm() {
              var result0;
              if (input.substr(pos, 6) === "NOTIFY") {
                result0 = "NOTIFY";
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"NOTIFY"');
                }
              }
              return result0;
            }
            function parse_REFERm() {
              var result0;
              if (input.substr(pos, 5) === "REFER") {
                result0 = "REFER";
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"REFER"');
                }
              }
              return result0;
            }
            function parse_Method() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_INVITEm();
              if (result0 === null) {
                result0 = parse_ACKm();
                if (result0 === null) {
                  result0 = parse_OPTIONSm();
                  if (result0 === null) {
                    result0 = parse_BYEm();
                    if (result0 === null) {
                      result0 = parse_CANCELm();
                      if (result0 === null) {
                        result0 = parse_REGISTERm();
                        if (result0 === null) {
                          result0 = parse_SUBSCRIBEm();
                          if (result0 === null) {
                            result0 = parse_NOTIFYm();
                            if (result0 === null) {
                              result0 = parse_REFERm();
                              if (result0 === null) {
                                result0 = parse_token();
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.method = input.substring(pos, offset2);
                  return data.method;
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Status_Line() {
              var result0, result1, result22, result3, result4;
              var pos0;
              pos0 = pos;
              result0 = parse_SIP_Version();
              if (result0 !== null) {
                result1 = parse_SP();
                if (result1 !== null) {
                  result22 = parse_Status_Code();
                  if (result22 !== null) {
                    result3 = parse_SP();
                    if (result3 !== null) {
                      result4 = parse_Reason_Phrase();
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Status_Code() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_extension_code();
              if (result0 !== null) {
                result0 = function(offset2, status_code) {
                  data.status_code = parseInt(status_code.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_extension_code() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_DIGIT();
              if (result0 !== null) {
                result1 = parse_DIGIT();
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Reason_Phrase() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result0 = [];
              result1 = parse_reserved();
              if (result1 === null) {
                result1 = parse_unreserved();
                if (result1 === null) {
                  result1 = parse_escaped();
                  if (result1 === null) {
                    result1 = parse_UTF8_NONASCII();
                    if (result1 === null) {
                      result1 = parse_UTF8_CONT();
                      if (result1 === null) {
                        result1 = parse_SP();
                        if (result1 === null) {
                          result1 = parse_HTAB();
                        }
                      }
                    }
                  }
                }
              }
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_reserved();
                if (result1 === null) {
                  result1 = parse_unreserved();
                  if (result1 === null) {
                    result1 = parse_escaped();
                    if (result1 === null) {
                      result1 = parse_UTF8_NONASCII();
                      if (result1 === null) {
                        result1 = parse_UTF8_CONT();
                        if (result1 === null) {
                          result1 = parse_SP();
                          if (result1 === null) {
                            result1 = parse_HTAB();
                          }
                        }
                      }
                    }
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.reason_phrase = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Allow_Events() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_event_type();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_event_type();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_event_type();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Call_ID() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_word();
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 64) {
                  result1 = "@";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"@"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_word();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Contact() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              result0 = parse_STAR();
              if (result0 === null) {
                pos1 = pos;
                result0 = parse_contact_param();
                if (result0 !== null) {
                  result1 = [];
                  pos2 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_contact_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                  while (result22 !== null) {
                    result1.push(result22);
                    pos2 = pos;
                    result22 = parse_COMMA();
                    if (result22 !== null) {
                      result3 = parse_contact_param();
                      if (result3 !== null) {
                        result22 = [result22, result3];
                      } else {
                        result22 = null;
                        pos = pos2;
                      }
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  }
                  if (result1 !== null) {
                    result0 = [result0, result1];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var idx, length;
                  length = data.multi_header.length;
                  for (idx = 0; idx < length; idx++) {
                    if (data.multi_header[idx].parsed === null) {
                      data = null;
                      break;
                    }
                  }
                  if (data !== null) {
                    data = data.multi_header;
                  } else {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_contact_param() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SIP_URI_noparams();
              if (result0 === null) {
                result0 = parse_name_addr();
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_contact_params();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_contact_params();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var header;
                  if (!data.multi_header) data.multi_header = [];
                  try {
                    header = new NameAddrHeader(data.uri, data.display_name, data.params);
                    delete data.uri;
                    delete data.display_name;
                    delete data.params;
                  } catch (e) {
                    header = null;
                  }
                  data.multi_header.push({
                    "possition": pos,
                    "offset": offset2,
                    "parsed": header
                  });
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_name_addr() {
              var result0, result1, result22, result3;
              var pos0;
              pos0 = pos;
              result0 = parse_display_name();
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result1 = parse_LAQUOT();
                if (result1 !== null) {
                  result22 = parse_SIP_URI();
                  if (result22 !== null) {
                    result3 = parse_RAQUOT();
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_display_name() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_LWS();
                if (result22 !== null) {
                  result3 = parse_token();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_LWS();
                  if (result22 !== null) {
                    result3 = parse_token();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 === null) {
                result0 = parse_quoted_string_clean();
              }
              if (result0 !== null) {
                result0 = function(offset2, display_name) {
                  if (typeof display_name === "string") {
                    data.display_name = display_name;
                  } else {
                    data.display_name = display_name[1].reduce(function(acc, cur) {
                      return acc + cur[0] + cur[1];
                    }, display_name[0]);
                  }
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_contact_params() {
              var result0;
              result0 = parse_c_p_q();
              if (result0 === null) {
                result0 = parse_c_p_expires();
                if (result0 === null) {
                  result0 = parse_generic_param();
                }
              }
              return result0;
            }
            function parse_c_p_q() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 1).toLowerCase() === "q") {
                result0 = input.substr(pos, 1);
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"q"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_qvalue();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, q) {
                  if (!data.params) data.params = {};
                  data.params["q"] = q;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_c_p_expires() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 7).toLowerCase() === "expires") {
                result0 = input.substr(pos, 7);
                pos += 7;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"expires"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_delta_seconds();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, expires) {
                  if (!data.params) data.params = {};
                  data.params["expires"] = expires;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_delta_seconds() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_DIGIT();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_DIGIT();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, delta_seconds) {
                  return parseInt(delta_seconds.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_qvalue() {
              var result0, result1, result22, result3, result4;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              if (input.charCodeAt(pos) === 48) {
                result0 = "0";
                pos++;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"0"');
                }
              }
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 46) {
                  result1 = ".";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"."');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_DIGIT();
                    result3 = result3 !== null ? result3 : "";
                    if (result3 !== null) {
                      result4 = parse_DIGIT();
                      result4 = result4 !== null ? result4 : "";
                      if (result4 !== null) {
                        result1 = [result1, result22, result3, result4];
                      } else {
                        result1 = null;
                        pos = pos2;
                      }
                    } else {
                      result1 = null;
                      pos = pos2;
                    }
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  return parseFloat(input.substring(pos, offset2));
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_generic_param() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                pos2 = pos;
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_gen_value();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, param, value) {
                  if (!data.params) data.params = {};
                  if (typeof value === "undefined") {
                    value = void 0;
                  } else {
                    value = value[1];
                  }
                  data.params[param.toLowerCase()] = value;
                }(pos0, result0[0], result0[1]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_gen_value() {
              var result0;
              result0 = parse_token();
              if (result0 === null) {
                result0 = parse_host();
                if (result0 === null) {
                  result0 = parse_quoted_string();
                }
              }
              return result0;
            }
            function parse_Content_Disposition() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_disp_type();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_disp_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_disp_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_disp_type() {
              var result0;
              if (input.substr(pos, 6).toLowerCase() === "render") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"render"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 7).toLowerCase() === "session") {
                  result0 = input.substr(pos, 7);
                  pos += 7;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"session"');
                  }
                }
                if (result0 === null) {
                  if (input.substr(pos, 4).toLowerCase() === "icon") {
                    result0 = input.substr(pos, 4);
                    pos += 4;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"icon"');
                    }
                  }
                  if (result0 === null) {
                    if (input.substr(pos, 5).toLowerCase() === "alert") {
                      result0 = input.substr(pos, 5);
                      pos += 5;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"alert"');
                      }
                    }
                    if (result0 === null) {
                      result0 = parse_token();
                    }
                  }
                }
              }
              return result0;
            }
            function parse_disp_param() {
              var result0;
              result0 = parse_handling_param();
              if (result0 === null) {
                result0 = parse_generic_param();
              }
              return result0;
            }
            function parse_handling_param() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 8).toLowerCase() === "handling") {
                result0 = input.substr(pos, 8);
                pos += 8;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"handling"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  if (input.substr(pos, 8).toLowerCase() === "optional") {
                    result22 = input.substr(pos, 8);
                    pos += 8;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"optional"');
                    }
                  }
                  if (result22 === null) {
                    if (input.substr(pos, 8).toLowerCase() === "required") {
                      result22 = input.substr(pos, 8);
                      pos += 8;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"required"');
                      }
                    }
                    if (result22 === null) {
                      result22 = parse_token();
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Content_Encoding() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_token();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_token();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Content_Length() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_DIGIT();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_DIGIT();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, length) {
                  data = parseInt(length.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Content_Type() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_media_type();
              if (result0 !== null) {
                result0 = function(offset2) {
                  data = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_media_type() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_m_type();
              if (result0 !== null) {
                result1 = parse_SLASH();
                if (result1 !== null) {
                  result22 = parse_m_subtype();
                  if (result22 !== null) {
                    result3 = [];
                    pos1 = pos;
                    result4 = parse_SEMI();
                    if (result4 !== null) {
                      result5 = parse_m_parameter();
                      if (result5 !== null) {
                        result4 = [result4, result5];
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    } else {
                      result4 = null;
                      pos = pos1;
                    }
                    while (result4 !== null) {
                      result3.push(result4);
                      pos1 = pos;
                      result4 = parse_SEMI();
                      if (result4 !== null) {
                        result5 = parse_m_parameter();
                        if (result5 !== null) {
                          result4 = [result4, result5];
                        } else {
                          result4 = null;
                          pos = pos1;
                        }
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    }
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_m_type() {
              var result0;
              result0 = parse_discrete_type();
              if (result0 === null) {
                result0 = parse_composite_type();
              }
              return result0;
            }
            function parse_discrete_type() {
              var result0;
              if (input.substr(pos, 4).toLowerCase() === "text") {
                result0 = input.substr(pos, 4);
                pos += 4;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"text"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 5).toLowerCase() === "image") {
                  result0 = input.substr(pos, 5);
                  pos += 5;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"image"');
                  }
                }
                if (result0 === null) {
                  if (input.substr(pos, 5).toLowerCase() === "audio") {
                    result0 = input.substr(pos, 5);
                    pos += 5;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"audio"');
                    }
                  }
                  if (result0 === null) {
                    if (input.substr(pos, 5).toLowerCase() === "video") {
                      result0 = input.substr(pos, 5);
                      pos += 5;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"video"');
                      }
                    }
                    if (result0 === null) {
                      if (input.substr(pos, 11).toLowerCase() === "application") {
                        result0 = input.substr(pos, 11);
                        pos += 11;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"application"');
                        }
                      }
                      if (result0 === null) {
                        result0 = parse_extension_token();
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_composite_type() {
              var result0;
              if (input.substr(pos, 7).toLowerCase() === "message") {
                result0 = input.substr(pos, 7);
                pos += 7;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"message"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 9).toLowerCase() === "multipart") {
                  result0 = input.substr(pos, 9);
                  pos += 9;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"multipart"');
                  }
                }
                if (result0 === null) {
                  result0 = parse_extension_token();
                }
              }
              return result0;
            }
            function parse_extension_token() {
              var result0;
              result0 = parse_token();
              if (result0 === null) {
                result0 = parse_x_token();
              }
              return result0;
            }
            function parse_x_token() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 2).toLowerCase() === "x-") {
                result0 = input.substr(pos, 2);
                pos += 2;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"x-"');
                }
              }
              if (result0 !== null) {
                result1 = parse_token();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_m_subtype() {
              var result0;
              result0 = parse_extension_token();
              if (result0 === null) {
                result0 = parse_token();
              }
              return result0;
            }
            function parse_m_parameter() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_m_value();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_m_value() {
              var result0;
              result0 = parse_token();
              if (result0 === null) {
                result0 = parse_quoted_string();
              }
              return result0;
            }
            function parse_CSeq() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_CSeq_value();
              if (result0 !== null) {
                result1 = parse_LWS();
                if (result1 !== null) {
                  result22 = parse_Method();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_CSeq_value() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_DIGIT();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_DIGIT();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, cseq_value) {
                  data.value = parseInt(cseq_value.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Expires() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_delta_seconds();
              if (result0 !== null) {
                result0 = function(offset2, expires) {
                  data = expires;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Event() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_event_type();
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_generic_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_generic_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, event_type) {
                  data.event = event_type.join("").toLowerCase();
                }(pos0, result0[0]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_event_type() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token_nodot();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                if (input.charCodeAt(pos) === 46) {
                  result22 = ".";
                  pos++;
                } else {
                  result22 = null;
                  if (reportFailures === 0) {
                    matchFailed('"."');
                  }
                }
                if (result22 !== null) {
                  result3 = parse_token_nodot();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  if (input.charCodeAt(pos) === 46) {
                    result22 = ".";
                    pos++;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"."');
                    }
                  }
                  if (result22 !== null) {
                    result3 = parse_token_nodot();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_From() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SIP_URI_noparams();
              if (result0 === null) {
                result0 = parse_name_addr();
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_from_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_from_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var tag = data.tag;
                  try {
                    data = new NameAddrHeader(data.uri, data.display_name, data.params);
                    if (tag) {
                      data.setParam("tag", tag);
                    }
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_from_param() {
              var result0;
              result0 = parse_tag_param();
              if (result0 === null) {
                result0 = parse_generic_param();
              }
              return result0;
            }
            function parse_tag_param() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 3).toLowerCase() === "tag") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"tag"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, tag) {
                  data.tag = tag;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Max_Forwards() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result1 = parse_DIGIT();
              if (result1 !== null) {
                result0 = [];
                while (result1 !== null) {
                  result0.push(result1);
                  result1 = parse_DIGIT();
                }
              } else {
                result0 = null;
              }
              if (result0 !== null) {
                result0 = function(offset2, forwards) {
                  data = parseInt(forwards.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Min_Expires() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_delta_seconds();
              if (result0 !== null) {
                result0 = function(offset2, min_expires) {
                  data = min_expires;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Name_Addr_Header() {
              var result0, result1, result22, result3, result4, result5, result6;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = [];
              result1 = parse_display_name();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_display_name();
              }
              if (result0 !== null) {
                result1 = parse_LAQUOT();
                if (result1 !== null) {
                  result22 = parse_SIP_URI();
                  if (result22 !== null) {
                    result3 = parse_RAQUOT();
                    if (result3 !== null) {
                      result4 = [];
                      pos2 = pos;
                      result5 = parse_SEMI();
                      if (result5 !== null) {
                        result6 = parse_generic_param();
                        if (result6 !== null) {
                          result5 = [result5, result6];
                        } else {
                          result5 = null;
                          pos = pos2;
                        }
                      } else {
                        result5 = null;
                        pos = pos2;
                      }
                      while (result5 !== null) {
                        result4.push(result5);
                        pos2 = pos;
                        result5 = parse_SEMI();
                        if (result5 !== null) {
                          result6 = parse_generic_param();
                          if (result6 !== null) {
                            result5 = [result5, result6];
                          } else {
                            result5 = null;
                            pos = pos2;
                          }
                        } else {
                          result5 = null;
                          pos = pos2;
                        }
                      }
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  try {
                    data = new NameAddrHeader(data.uri, data.display_name, data.params);
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Proxy_Authenticate() {
              var result0;
              result0 = parse_challenge();
              return result0;
            }
            function parse_challenge() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              if (input.substr(pos, 6).toLowerCase() === "digest") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"Digest"');
                }
              }
              if (result0 !== null) {
                result1 = parse_LWS();
                if (result1 !== null) {
                  result22 = parse_digest_cln();
                  if (result22 !== null) {
                    result3 = [];
                    pos1 = pos;
                    result4 = parse_COMMA();
                    if (result4 !== null) {
                      result5 = parse_digest_cln();
                      if (result5 !== null) {
                        result4 = [result4, result5];
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    } else {
                      result4 = null;
                      pos = pos1;
                    }
                    while (result4 !== null) {
                      result3.push(result4);
                      pos1 = pos;
                      result4 = parse_COMMA();
                      if (result4 !== null) {
                        result5 = parse_digest_cln();
                        if (result5 !== null) {
                          result4 = [result4, result5];
                        } else {
                          result4 = null;
                          pos = pos1;
                        }
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    }
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              if (result0 === null) {
                result0 = parse_other_challenge();
              }
              return result0;
            }
            function parse_other_challenge() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = parse_LWS();
                if (result1 !== null) {
                  result22 = parse_auth_param();
                  if (result22 !== null) {
                    result3 = [];
                    pos1 = pos;
                    result4 = parse_COMMA();
                    if (result4 !== null) {
                      result5 = parse_auth_param();
                      if (result5 !== null) {
                        result4 = [result4, result5];
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    } else {
                      result4 = null;
                      pos = pos1;
                    }
                    while (result4 !== null) {
                      result3.push(result4);
                      pos1 = pos;
                      result4 = parse_COMMA();
                      if (result4 !== null) {
                        result5 = parse_auth_param();
                        if (result5 !== null) {
                          result4 = [result4, result5];
                        } else {
                          result4 = null;
                          pos = pos1;
                        }
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    }
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_auth_param() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 === null) {
                    result22 = parse_quoted_string();
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_digest_cln() {
              var result0;
              result0 = parse_realm();
              if (result0 === null) {
                result0 = parse_domain();
                if (result0 === null) {
                  result0 = parse_nonce();
                  if (result0 === null) {
                    result0 = parse_opaque();
                    if (result0 === null) {
                      result0 = parse_stale();
                      if (result0 === null) {
                        result0 = parse_algorithm();
                        if (result0 === null) {
                          result0 = parse_qop_options();
                          if (result0 === null) {
                            result0 = parse_auth_param();
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_realm() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 5).toLowerCase() === "realm") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"realm"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_realm_value();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_realm_value() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_quoted_string_clean();
              if (result0 !== null) {
                result0 = function(offset2, realm) {
                  data.realm = realm;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_domain() {
              var result0, result1, result22, result3, result4, result5, result6;
              var pos0, pos1;
              pos0 = pos;
              if (input.substr(pos, 6).toLowerCase() === "domain") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"domain"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_LDQUOT();
                  if (result22 !== null) {
                    result3 = parse_URI();
                    if (result3 !== null) {
                      result4 = [];
                      pos1 = pos;
                      result6 = parse_SP();
                      if (result6 !== null) {
                        result5 = [];
                        while (result6 !== null) {
                          result5.push(result6);
                          result6 = parse_SP();
                        }
                      } else {
                        result5 = null;
                      }
                      if (result5 !== null) {
                        result6 = parse_URI();
                        if (result6 !== null) {
                          result5 = [result5, result6];
                        } else {
                          result5 = null;
                          pos = pos1;
                        }
                      } else {
                        result5 = null;
                        pos = pos1;
                      }
                      while (result5 !== null) {
                        result4.push(result5);
                        pos1 = pos;
                        result6 = parse_SP();
                        if (result6 !== null) {
                          result5 = [];
                          while (result6 !== null) {
                            result5.push(result6);
                            result6 = parse_SP();
                          }
                        } else {
                          result5 = null;
                        }
                        if (result5 !== null) {
                          result6 = parse_URI();
                          if (result6 !== null) {
                            result5 = [result5, result6];
                          } else {
                            result5 = null;
                            pos = pos1;
                          }
                        } else {
                          result5 = null;
                          pos = pos1;
                        }
                      }
                      if (result4 !== null) {
                        result5 = parse_RDQUOT();
                        if (result5 !== null) {
                          result0 = [result0, result1, result22, result3, result4, result5];
                        } else {
                          result0 = null;
                          pos = pos0;
                        }
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_URI() {
              var result0;
              result0 = parse_absoluteURI();
              if (result0 === null) {
                result0 = parse_abs_path();
              }
              return result0;
            }
            function parse_nonce() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 5).toLowerCase() === "nonce") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"nonce"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_nonce_value();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_nonce_value() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_quoted_string_clean();
              if (result0 !== null) {
                result0 = function(offset2, nonce) {
                  data.nonce = nonce;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_opaque() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 6).toLowerCase() === "opaque") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"opaque"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_quoted_string_clean();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, opaque) {
                  data.opaque = opaque;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_stale() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              if (input.substr(pos, 5).toLowerCase() === "stale") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"stale"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  pos1 = pos;
                  if (input.substr(pos, 4).toLowerCase() === "true") {
                    result22 = input.substr(pos, 4);
                    pos += 4;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"true"');
                    }
                  }
                  if (result22 !== null) {
                    result22 = function(offset2) {
                      data.stale = true;
                    }(pos1);
                  }
                  if (result22 === null) {
                    pos = pos1;
                  }
                  if (result22 === null) {
                    pos1 = pos;
                    if (input.substr(pos, 5).toLowerCase() === "false") {
                      result22 = input.substr(pos, 5);
                      pos += 5;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"false"');
                      }
                    }
                    if (result22 !== null) {
                      result22 = function(offset2) {
                        data.stale = false;
                      }(pos1);
                    }
                    if (result22 === null) {
                      pos = pos1;
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_algorithm() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 9).toLowerCase() === "algorithm") {
                result0 = input.substr(pos, 9);
                pos += 9;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"algorithm"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  if (input.substr(pos, 3).toLowerCase() === "md5") {
                    result22 = input.substr(pos, 3);
                    pos += 3;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"MD5"');
                    }
                  }
                  if (result22 === null) {
                    if (input.substr(pos, 8).toLowerCase() === "md5-sess") {
                      result22 = input.substr(pos, 8);
                      pos += 8;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"MD5-sess"');
                      }
                    }
                    if (result22 === null) {
                      result22 = parse_token();
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, algorithm) {
                  data.algorithm = algorithm.toUpperCase();
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_qop_options() {
              var result0, result1, result22, result3, result4, result5, result6;
              var pos0, pos1, pos2;
              pos0 = pos;
              if (input.substr(pos, 3).toLowerCase() === "qop") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"qop"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_LDQUOT();
                  if (result22 !== null) {
                    pos1 = pos;
                    result3 = parse_qop_value();
                    if (result3 !== null) {
                      result4 = [];
                      pos2 = pos;
                      if (input.charCodeAt(pos) === 44) {
                        result5 = ",";
                        pos++;
                      } else {
                        result5 = null;
                        if (reportFailures === 0) {
                          matchFailed('","');
                        }
                      }
                      if (result5 !== null) {
                        result6 = parse_qop_value();
                        if (result6 !== null) {
                          result5 = [result5, result6];
                        } else {
                          result5 = null;
                          pos = pos2;
                        }
                      } else {
                        result5 = null;
                        pos = pos2;
                      }
                      while (result5 !== null) {
                        result4.push(result5);
                        pos2 = pos;
                        if (input.charCodeAt(pos) === 44) {
                          result5 = ",";
                          pos++;
                        } else {
                          result5 = null;
                          if (reportFailures === 0) {
                            matchFailed('","');
                          }
                        }
                        if (result5 !== null) {
                          result6 = parse_qop_value();
                          if (result6 !== null) {
                            result5 = [result5, result6];
                          } else {
                            result5 = null;
                            pos = pos2;
                          }
                        } else {
                          result5 = null;
                          pos = pos2;
                        }
                      }
                      if (result4 !== null) {
                        result3 = [result3, result4];
                      } else {
                        result3 = null;
                        pos = pos1;
                      }
                    } else {
                      result3 = null;
                      pos = pos1;
                    }
                    if (result3 !== null) {
                      result4 = parse_RDQUOT();
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_qop_value() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 8).toLowerCase() === "auth-int") {
                result0 = input.substr(pos, 8);
                pos += 8;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"auth-int"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 4).toLowerCase() === "auth") {
                  result0 = input.substr(pos, 4);
                  pos += 4;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"auth"');
                  }
                }
                if (result0 === null) {
                  result0 = parse_token();
                }
              }
              if (result0 !== null) {
                result0 = function(offset2, qop_value) {
                  data.qop || (data.qop = []);
                  data.qop.push(qop_value.toLowerCase());
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Proxy_Require() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_token();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_token();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Record_Route() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_rec_route();
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_rec_route();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_rec_route();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var idx, length;
                  length = data.multi_header.length;
                  for (idx = 0; idx < length; idx++) {
                    if (data.multi_header[idx].parsed === null) {
                      data = null;
                      break;
                    }
                  }
                  if (data !== null) {
                    data = data.multi_header;
                  } else {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_rec_route() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_name_addr();
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_generic_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_generic_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var header;
                  if (!data.multi_header) data.multi_header = [];
                  try {
                    header = new NameAddrHeader(data.uri, data.display_name, data.params);
                    delete data.uri;
                    delete data.display_name;
                    delete data.params;
                  } catch (e) {
                    header = null;
                  }
                  data.multi_header.push({
                    "possition": pos,
                    "offset": offset2,
                    "parsed": header
                  });
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Reason() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 3).toLowerCase() === "sip") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"SIP"');
                }
              }
              if (result0 === null) {
                result0 = parse_token();
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_reason_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_reason_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, protocol) {
                  data.protocol = protocol.toLowerCase();
                  if (!data.params) data.params = {};
                  if (data.params.text && data.params.text[0] === '"') {
                    var text = data.params.text;
                    data.text = text.substring(1, text.length - 1);
                    delete data.params.text;
                  }
                }(pos0, result0[0]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_reason_param() {
              var result0;
              result0 = parse_reason_cause();
              if (result0 === null) {
                result0 = parse_generic_param();
              }
              return result0;
            }
            function parse_reason_cause() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 5).toLowerCase() === "cause") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"cause"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result3 = parse_DIGIT();
                  if (result3 !== null) {
                    result22 = [];
                    while (result3 !== null) {
                      result22.push(result3);
                      result3 = parse_DIGIT();
                    }
                  } else {
                    result22 = null;
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, cause) {
                  data.cause = parseInt(cause.join(""));
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Require() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_token();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_token();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Route() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_route_param();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_route_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_route_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_route_param() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_name_addr();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_generic_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_generic_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Subscription_State() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_substate_value();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_subexp_params();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_subexp_params();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_substate_value() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 6).toLowerCase() === "active") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"active"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 7).toLowerCase() === "pending") {
                  result0 = input.substr(pos, 7);
                  pos += 7;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"pending"');
                  }
                }
                if (result0 === null) {
                  if (input.substr(pos, 10).toLowerCase() === "terminated") {
                    result0 = input.substr(pos, 10);
                    pos += 10;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"terminated"');
                    }
                  }
                  if (result0 === null) {
                    result0 = parse_token();
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.state = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_subexp_params() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 6).toLowerCase() === "reason") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"reason"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_event_reason_value();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, reason) {
                  if (typeof reason !== "undefined") data.reason = reason;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              if (result0 === null) {
                pos0 = pos;
                pos1 = pos;
                if (input.substr(pos, 7).toLowerCase() === "expires") {
                  result0 = input.substr(pos, 7);
                  pos += 7;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"expires"');
                  }
                }
                if (result0 !== null) {
                  result1 = parse_EQUAL();
                  if (result1 !== null) {
                    result22 = parse_delta_seconds();
                    if (result22 !== null) {
                      result0 = [result0, result1, result22];
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
                if (result0 !== null) {
                  result0 = function(offset2, expires) {
                    if (typeof expires !== "undefined") data.expires = expires;
                  }(pos0, result0[2]);
                }
                if (result0 === null) {
                  pos = pos0;
                }
                if (result0 === null) {
                  pos0 = pos;
                  pos1 = pos;
                  if (input.substr(pos, 11).toLowerCase() === "retry_after") {
                    result0 = input.substr(pos, 11);
                    pos += 11;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"retry_after"');
                    }
                  }
                  if (result0 !== null) {
                    result1 = parse_EQUAL();
                    if (result1 !== null) {
                      result22 = parse_delta_seconds();
                      if (result22 !== null) {
                        result0 = [result0, result1, result22];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                  if (result0 !== null) {
                    result0 = function(offset2, retry_after) {
                      if (typeof retry_after !== "undefined") data.retry_after = retry_after;
                    }(pos0, result0[2]);
                  }
                  if (result0 === null) {
                    pos = pos0;
                  }
                  if (result0 === null) {
                    result0 = parse_generic_param();
                  }
                }
              }
              return result0;
            }
            function parse_event_reason_value() {
              var result0;
              if (input.substr(pos, 11).toLowerCase() === "deactivated") {
                result0 = input.substr(pos, 11);
                pos += 11;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"deactivated"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 9).toLowerCase() === "probation") {
                  result0 = input.substr(pos, 9);
                  pos += 9;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"probation"');
                  }
                }
                if (result0 === null) {
                  if (input.substr(pos, 8).toLowerCase() === "rejected") {
                    result0 = input.substr(pos, 8);
                    pos += 8;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"rejected"');
                    }
                  }
                  if (result0 === null) {
                    if (input.substr(pos, 7).toLowerCase() === "timeout") {
                      result0 = input.substr(pos, 7);
                      pos += 7;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"timeout"');
                      }
                    }
                    if (result0 === null) {
                      if (input.substr(pos, 6).toLowerCase() === "giveup") {
                        result0 = input.substr(pos, 6);
                        pos += 6;
                      } else {
                        result0 = null;
                        if (reportFailures === 0) {
                          matchFailed('"giveup"');
                        }
                      }
                      if (result0 === null) {
                        if (input.substr(pos, 10).toLowerCase() === "noresource") {
                          result0 = input.substr(pos, 10);
                          pos += 10;
                        } else {
                          result0 = null;
                          if (reportFailures === 0) {
                            matchFailed('"noresource"');
                          }
                        }
                        if (result0 === null) {
                          if (input.substr(pos, 9).toLowerCase() === "invariant") {
                            result0 = input.substr(pos, 9);
                            pos += 9;
                          } else {
                            result0 = null;
                            if (reportFailures === 0) {
                              matchFailed('"invariant"');
                            }
                          }
                          if (result0 === null) {
                            result0 = parse_token();
                          }
                        }
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_Subject() {
              var result0;
              result0 = parse_TEXT_UTF8_TRIM();
              result0 = result0 !== null ? result0 : "";
              return result0;
            }
            function parse_Supported() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_token();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_token();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              result0 = result0 !== null ? result0 : "";
              return result0;
            }
            function parse_To() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SIP_URI_noparams();
              if (result0 === null) {
                result0 = parse_name_addr();
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_to_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_to_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  var tag = data.tag;
                  try {
                    data = new NameAddrHeader(data.uri, data.display_name, data.params);
                    if (tag) {
                      data.setParam("tag", tag);
                    }
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_to_param() {
              var result0;
              result0 = parse_tag_param();
              if (result0 === null) {
                result0 = parse_generic_param();
              }
              return result0;
            }
            function parse_Via() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_via_param();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_COMMA();
                if (result22 !== null) {
                  result3 = parse_via_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_COMMA();
                  if (result22 !== null) {
                    result3 = parse_via_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_via_param() {
              var result0, result1, result22, result3, result4, result5;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_sent_protocol();
              if (result0 !== null) {
                result1 = parse_LWS();
                if (result1 !== null) {
                  result22 = parse_sent_by();
                  if (result22 !== null) {
                    result3 = [];
                    pos1 = pos;
                    result4 = parse_SEMI();
                    if (result4 !== null) {
                      result5 = parse_via_params();
                      if (result5 !== null) {
                        result4 = [result4, result5];
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    } else {
                      result4 = null;
                      pos = pos1;
                    }
                    while (result4 !== null) {
                      result3.push(result4);
                      pos1 = pos;
                      result4 = parse_SEMI();
                      if (result4 !== null) {
                        result5 = parse_via_params();
                        if (result5 !== null) {
                          result4 = [result4, result5];
                        } else {
                          result4 = null;
                          pos = pos1;
                        }
                      } else {
                        result4 = null;
                        pos = pos1;
                      }
                    }
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_via_params() {
              var result0;
              result0 = parse_via_ttl();
              if (result0 === null) {
                result0 = parse_via_maddr();
                if (result0 === null) {
                  result0 = parse_via_received();
                  if (result0 === null) {
                    result0 = parse_via_branch();
                    if (result0 === null) {
                      result0 = parse_response_port();
                      if (result0 === null) {
                        result0 = parse_generic_param();
                      }
                    }
                  }
                }
              }
              return result0;
            }
            function parse_via_ttl() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 3).toLowerCase() === "ttl") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"ttl"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_ttl();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, via_ttl_value) {
                  data.ttl = via_ttl_value;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_via_maddr() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 5).toLowerCase() === "maddr") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"maddr"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_host();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, via_maddr) {
                  data.maddr = via_maddr;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_via_received() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 8).toLowerCase() === "received") {
                result0 = input.substr(pos, 8);
                pos += 8;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"received"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_IPv4address();
                  if (result22 === null) {
                    result22 = parse_IPv6address();
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, via_received) {
                  data.received = via_received;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_via_branch() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 6).toLowerCase() === "branch") {
                result0 = input.substr(pos, 6);
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"branch"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, via_branch) {
                  data.branch = via_branch;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_response_port() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              if (input.substr(pos, 5).toLowerCase() === "rport") {
                result0 = input.substr(pos, 5);
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"rport"');
                }
              }
              if (result0 !== null) {
                pos1 = pos;
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_rport();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos1;
                  }
                } else {
                  result1 = null;
                  pos = pos1;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_rport() {
              var result0, result1, result22, result3, result4;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_DIGIT();
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result1 = parse_DIGIT();
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_DIGIT();
                    result3 = result3 !== null ? result3 : "";
                    if (result3 !== null) {
                      result4 = parse_DIGIT();
                      result4 = result4 !== null ? result4 : "";
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, rport) {
                  data.rport = parseInt(rport.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_sent_protocol() {
              var result0, result1, result22, result3, result4;
              var pos0;
              pos0 = pos;
              result0 = parse_protocol_name();
              if (result0 !== null) {
                result1 = parse_SLASH();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result3 = parse_SLASH();
                    if (result3 !== null) {
                      result4 = parse_transport();
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos0;
                      }
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_protocol_name() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 3).toLowerCase() === "sip") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"SIP"');
                }
              }
              if (result0 === null) {
                result0 = parse_token();
              }
              if (result0 !== null) {
                result0 = function(offset2, via_protocol) {
                  data.protocol = via_protocol;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_transport() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 3).toLowerCase() === "udp") {
                result0 = input.substr(pos, 3);
                pos += 3;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"UDP"');
                }
              }
              if (result0 === null) {
                if (input.substr(pos, 3).toLowerCase() === "tcp") {
                  result0 = input.substr(pos, 3);
                  pos += 3;
                } else {
                  result0 = null;
                  if (reportFailures === 0) {
                    matchFailed('"TCP"');
                  }
                }
                if (result0 === null) {
                  if (input.substr(pos, 3).toLowerCase() === "tls") {
                    result0 = input.substr(pos, 3);
                    pos += 3;
                  } else {
                    result0 = null;
                    if (reportFailures === 0) {
                      matchFailed('"TLS"');
                    }
                  }
                  if (result0 === null) {
                    if (input.substr(pos, 4).toLowerCase() === "sctp") {
                      result0 = input.substr(pos, 4);
                      pos += 4;
                    } else {
                      result0 = null;
                      if (reportFailures === 0) {
                        matchFailed('"SCTP"');
                      }
                    }
                    if (result0 === null) {
                      result0 = parse_token();
                    }
                  }
                }
              }
              if (result0 !== null) {
                result0 = function(offset2, via_transport) {
                  data.transport = via_transport;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_sent_by() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_via_host();
              if (result0 !== null) {
                pos1 = pos;
                result1 = parse_COLON();
                if (result1 !== null) {
                  result22 = parse_via_port();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos1;
                  }
                } else {
                  result1 = null;
                  pos = pos1;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_via_host() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_IPv4address();
              if (result0 === null) {
                result0 = parse_IPv6reference();
                if (result0 === null) {
                  result0 = parse_hostname();
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.host = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_via_port() {
              var result0, result1, result22, result3, result4;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_DIGIT();
              result0 = result0 !== null ? result0 : "";
              if (result0 !== null) {
                result1 = parse_DIGIT();
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result3 = parse_DIGIT();
                    result3 = result3 !== null ? result3 : "";
                    if (result3 !== null) {
                      result4 = parse_DIGIT();
                      result4 = result4 !== null ? result4 : "";
                      if (result4 !== null) {
                        result0 = [result0, result1, result22, result3, result4];
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, via_sent_by_port) {
                  data.port = parseInt(via_sent_by_port.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_ttl() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_DIGIT();
              if (result0 !== null) {
                result1 = parse_DIGIT();
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result22 = parse_DIGIT();
                  result22 = result22 !== null ? result22 : "";
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, ttl) {
                  return parseInt(ttl.join(""));
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_WWW_Authenticate() {
              var result0;
              result0 = parse_challenge();
              return result0;
            }
            function parse_Session_Expires() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_s_e_expires();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_s_e_params();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_s_e_params();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_s_e_expires() {
              var result0;
              var pos0;
              pos0 = pos;
              result0 = parse_delta_seconds();
              if (result0 !== null) {
                result0 = function(offset2, expires) {
                  data.expires = expires;
                }(pos0, result0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_s_e_params() {
              var result0;
              result0 = parse_s_e_refresher();
              if (result0 === null) {
                result0 = parse_generic_param();
              }
              return result0;
            }
            function parse_s_e_refresher() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 9).toLowerCase() === "refresher") {
                result0 = input.substr(pos, 9);
                pos += 9;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"refresher"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  if (input.substr(pos, 3).toLowerCase() === "uac") {
                    result22 = input.substr(pos, 3);
                    pos += 3;
                  } else {
                    result22 = null;
                    if (reportFailures === 0) {
                      matchFailed('"uac"');
                    }
                  }
                  if (result22 === null) {
                    if (input.substr(pos, 3).toLowerCase() === "uas") {
                      result22 = input.substr(pos, 3);
                      pos += 3;
                    } else {
                      result22 = null;
                      if (reportFailures === 0) {
                        matchFailed('"uas"');
                      }
                    }
                  }
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, s_e_refresher_value) {
                  data.refresher = s_e_refresher_value.toLowerCase();
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_extension_header() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_token();
              if (result0 !== null) {
                result1 = parse_HCOLON();
                if (result1 !== null) {
                  result22 = parse_header_value();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_header_value() {
              var result0, result1;
              result0 = [];
              result1 = parse_TEXT_UTF8char();
              if (result1 === null) {
                result1 = parse_UTF8_CONT();
                if (result1 === null) {
                  result1 = parse_LWS();
                }
              }
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_TEXT_UTF8char();
                if (result1 === null) {
                  result1 = parse_UTF8_CONT();
                  if (result1 === null) {
                    result1 = parse_LWS();
                  }
                }
              }
              return result0;
            }
            function parse_message_body() {
              var result0, result1;
              result0 = [];
              result1 = parse_OCTET();
              while (result1 !== null) {
                result0.push(result1);
                result1 = parse_OCTET();
              }
              return result0;
            }
            function parse_uuid_URI() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 5) === "uuid:") {
                result0 = "uuid:";
                pos += 5;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"uuid:"');
                }
              }
              if (result0 !== null) {
                result1 = parse_uuid();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_uuid() {
              var result0, result1, result22, result3, result4, result5, result6, result7, result8;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_hex8();
              if (result0 !== null) {
                if (input.charCodeAt(pos) === 45) {
                  result1 = "-";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"-"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_hex4();
                  if (result22 !== null) {
                    if (input.charCodeAt(pos) === 45) {
                      result3 = "-";
                      pos++;
                    } else {
                      result3 = null;
                      if (reportFailures === 0) {
                        matchFailed('"-"');
                      }
                    }
                    if (result3 !== null) {
                      result4 = parse_hex4();
                      if (result4 !== null) {
                        if (input.charCodeAt(pos) === 45) {
                          result5 = "-";
                          pos++;
                        } else {
                          result5 = null;
                          if (reportFailures === 0) {
                            matchFailed('"-"');
                          }
                        }
                        if (result5 !== null) {
                          result6 = parse_hex4();
                          if (result6 !== null) {
                            if (input.charCodeAt(pos) === 45) {
                              result7 = "-";
                              pos++;
                            } else {
                              result7 = null;
                              if (reportFailures === 0) {
                                matchFailed('"-"');
                              }
                            }
                            if (result7 !== null) {
                              result8 = parse_hex12();
                              if (result8 !== null) {
                                result0 = [result0, result1, result22, result3, result4, result5, result6, result7, result8];
                              } else {
                                result0 = null;
                                pos = pos1;
                              }
                            } else {
                              result0 = null;
                              pos = pos1;
                            }
                          } else {
                            result0 = null;
                            pos = pos1;
                          }
                        } else {
                          result0 = null;
                          pos = pos1;
                        }
                      } else {
                        result0 = null;
                        pos = pos1;
                      }
                    } else {
                      result0 = null;
                      pos = pos1;
                    }
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, uuid) {
                  data = input.substring(pos + 5, offset2);
                }(pos0, result0[0]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_hex4() {
              var result0, result1, result22, result3;
              var pos0;
              pos0 = pos;
              result0 = parse_HEXDIG();
              if (result0 !== null) {
                result1 = parse_HEXDIG();
                if (result1 !== null) {
                  result22 = parse_HEXDIG();
                  if (result22 !== null) {
                    result3 = parse_HEXDIG();
                    if (result3 !== null) {
                      result0 = [result0, result1, result22, result3];
                    } else {
                      result0 = null;
                      pos = pos0;
                    }
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_hex8() {
              var result0, result1;
              var pos0;
              pos0 = pos;
              result0 = parse_hex4();
              if (result0 !== null) {
                result1 = parse_hex4();
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_hex12() {
              var result0, result1, result22;
              var pos0;
              pos0 = pos;
              result0 = parse_hex4();
              if (result0 !== null) {
                result1 = parse_hex4();
                if (result1 !== null) {
                  result22 = parse_hex4();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos0;
                  }
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_Refer_To() {
              var result0, result1, result22, result3;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_SIP_URI_noparams();
              if (result0 === null) {
                result0 = parse_name_addr();
              }
              if (result0 !== null) {
                result1 = [];
                pos2 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_generic_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                } else {
                  result22 = null;
                  pos = pos2;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos2 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_generic_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos2;
                    }
                  } else {
                    result22 = null;
                    pos = pos2;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  try {
                    data = new NameAddrHeader(data.uri, data.display_name, data.params);
                  } catch (e) {
                    data = -1;
                  }
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_Replaces() {
              var result0, result1, result22, result3;
              var pos0, pos1;
              pos0 = pos;
              result0 = parse_call_id();
              if (result0 !== null) {
                result1 = [];
                pos1 = pos;
                result22 = parse_SEMI();
                if (result22 !== null) {
                  result3 = parse_replaces_param();
                  if (result3 !== null) {
                    result22 = [result22, result3];
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                } else {
                  result22 = null;
                  pos = pos1;
                }
                while (result22 !== null) {
                  result1.push(result22);
                  pos1 = pos;
                  result22 = parse_SEMI();
                  if (result22 !== null) {
                    result3 = parse_replaces_param();
                    if (result3 !== null) {
                      result22 = [result22, result3];
                    } else {
                      result22 = null;
                      pos = pos1;
                    }
                  } else {
                    result22 = null;
                    pos = pos1;
                  }
                }
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos0;
                }
              } else {
                result0 = null;
                pos = pos0;
              }
              return result0;
            }
            function parse_call_id() {
              var result0, result1, result22;
              var pos0, pos1, pos2;
              pos0 = pos;
              pos1 = pos;
              result0 = parse_word();
              if (result0 !== null) {
                pos2 = pos;
                if (input.charCodeAt(pos) === 64) {
                  result1 = "@";
                  pos++;
                } else {
                  result1 = null;
                  if (reportFailures === 0) {
                    matchFailed('"@"');
                  }
                }
                if (result1 !== null) {
                  result22 = parse_word();
                  if (result22 !== null) {
                    result1 = [result1, result22];
                  } else {
                    result1 = null;
                    pos = pos2;
                  }
                } else {
                  result1 = null;
                  pos = pos2;
                }
                result1 = result1 !== null ? result1 : "";
                if (result1 !== null) {
                  result0 = [result0, result1];
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.call_id = input.substring(pos, offset2);
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_replaces_param() {
              var result0;
              result0 = parse_to_tag();
              if (result0 === null) {
                result0 = parse_from_tag();
                if (result0 === null) {
                  result0 = parse_early_flag();
                  if (result0 === null) {
                    result0 = parse_generic_param();
                  }
                }
              }
              return result0;
            }
            function parse_to_tag() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 6) === "to-tag") {
                result0 = "to-tag";
                pos += 6;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"to-tag"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, to_tag) {
                  data.to_tag = to_tag;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_from_tag() {
              var result0, result1, result22;
              var pos0, pos1;
              pos0 = pos;
              pos1 = pos;
              if (input.substr(pos, 8) === "from-tag") {
                result0 = "from-tag";
                pos += 8;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"from-tag"');
                }
              }
              if (result0 !== null) {
                result1 = parse_EQUAL();
                if (result1 !== null) {
                  result22 = parse_token();
                  if (result22 !== null) {
                    result0 = [result0, result1, result22];
                  } else {
                    result0 = null;
                    pos = pos1;
                  }
                } else {
                  result0 = null;
                  pos = pos1;
                }
              } else {
                result0 = null;
                pos = pos1;
              }
              if (result0 !== null) {
                result0 = function(offset2, from_tag) {
                  data.from_tag = from_tag;
                }(pos0, result0[2]);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function parse_early_flag() {
              var result0;
              var pos0;
              pos0 = pos;
              if (input.substr(pos, 10) === "early-only") {
                result0 = "early-only";
                pos += 10;
              } else {
                result0 = null;
                if (reportFailures === 0) {
                  matchFailed('"early-only"');
                }
              }
              if (result0 !== null) {
                result0 = function(offset2) {
                  data.early_only = true;
                }(pos0);
              }
              if (result0 === null) {
                pos = pos0;
              }
              return result0;
            }
            function cleanupExpected(expected) {
              expected.sort();
              var lastExpected = null;
              var cleanExpected = [];
              for (var i = 0; i < expected.length; i++) {
                if (expected[i] !== lastExpected) {
                  cleanExpected.push(expected[i]);
                  lastExpected = expected[i];
                }
              }
              return cleanExpected;
            }
            function computeErrorPosition() {
              var line = 1;
              var column = 1;
              var seenCR = false;
              for (var i = 0; i < Math.max(pos, rightmostFailuresPos); i++) {
                var ch = input.charAt(i);
                if (ch === "\n") {
                  if (!seenCR) {
                    line++;
                  }
                  column = 1;
                  seenCR = false;
                } else if (ch === "\r" || ch === "\u2028" || ch === "\u2029") {
                  line++;
                  column = 1;
                  seenCR = true;
                } else {
                  column++;
                  seenCR = false;
                }
              }
              return {
                line,
                column
              };
            }
            var URI = require_URI();
            var NameAddrHeader = require_NameAddrHeader();
            var data = {};
            var result2 = parseFunctions[startRule]();
            if (result2 === null || pos !== input.length) {
              var offset = Math.max(pos, rightmostFailuresPos);
              var found = offset < input.length ? input.charAt(offset) : null;
              var errorPosition = computeErrorPosition();
              new this.SyntaxError(cleanupExpected(rightmostFailuresExpected), found, offset, errorPosition.line, errorPosition.column);
              return -1;
            }
            return data;
          },
          /* Returns the parser source code. */
          toSource: function toSource() {
            return this._source;
          }
        };
        result.SyntaxError = function(expected, found, offset, line, column) {
          function buildMessage(expected2, found2) {
            var expectedHumanized, foundHumanized;
            switch (expected2.length) {
              case 0:
                expectedHumanized = "end of input";
                break;
              case 1:
                expectedHumanized = expected2[0];
                break;
              default:
                expectedHumanized = expected2.slice(0, expected2.length - 1).join(", ") + " or " + expected2[expected2.length - 1];
            }
            foundHumanized = found2 ? quote(found2) : "end of input";
            return "Expected " + expectedHumanized + " but " + foundHumanized + " found.";
          }
          this.name = "SyntaxError";
          this.expected = expected;
          this.found = found;
          this.message = buildMessage(expected, found);
          this.offset = offset;
          this.line = line;
          this.column = column;
        };
        result.SyntaxError.prototype = Error.prototype;
        return result;
      }();
    }
  });

  // node_modules/jssip/lib-es5/URI.js
  var require_URI = __commonJS({
    "node_modules/jssip/lib-es5/URI.js"(exports, module) {
      "use strict";
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var JsSIP_C = require_Constants();
      var Utils = require_Utils();
      var Grammar = require_Grammar();
      module.exports = /* @__PURE__ */ function() {
        _createClass(URI, null, [{
          key: "parse",
          /**
            * Parse the given string and returns a JsSIP.URI instance or undefined if
            * it is an invalid URI.
            */
          value: function parse(uri) {
            uri = Grammar.parse(uri, "SIP_URI");
            if (uri !== -1) {
              return uri;
            } else {
              return void 0;
            }
          }
        }]);
        function URI(scheme, user, host, port) {
          var parameters = arguments.length > 4 && arguments[4] !== void 0 ? arguments[4] : {};
          var headers = arguments.length > 5 && arguments[5] !== void 0 ? arguments[5] : {};
          _classCallCheck(this, URI);
          if (!host) {
            throw new TypeError('missing or invalid "host" parameter');
          }
          this._parameters = {};
          this._headers = {};
          this._scheme = scheme || JsSIP_C.SIP;
          this._user = user;
          this._host = host;
          this._port = port;
          for (var param in parameters) {
            if (Object.prototype.hasOwnProperty.call(parameters, param)) {
              this.setParam(param, parameters[param]);
            }
          }
          for (var header in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, header)) {
              this.setHeader(header, headers[header]);
            }
          }
        }
        _createClass(URI, [{
          key: "setParam",
          value: function setParam(key, value) {
            if (key) {
              this._parameters[key.toLowerCase()] = typeof value === "undefined" || value === null ? null : value.toString();
            }
          }
        }, {
          key: "getParam",
          value: function getParam(key) {
            if (key) {
              return this._parameters[key.toLowerCase()];
            }
          }
        }, {
          key: "hasParam",
          value: function hasParam(key) {
            if (key) {
              return this._parameters.hasOwnProperty(key.toLowerCase()) && true || false;
            }
          }
        }, {
          key: "deleteParam",
          value: function deleteParam(parameter) {
            parameter = parameter.toLowerCase();
            if (this._parameters.hasOwnProperty(parameter)) {
              var value = this._parameters[parameter];
              delete this._parameters[parameter];
              return value;
            }
          }
        }, {
          key: "clearParams",
          value: function clearParams() {
            this._parameters = {};
          }
        }, {
          key: "setHeader",
          value: function setHeader(name, value) {
            this._headers[Utils.headerize(name)] = Array.isArray(value) ? value : [value];
          }
        }, {
          key: "getHeader",
          value: function getHeader(name) {
            if (name) {
              return this._headers[Utils.headerize(name)];
            }
          }
        }, {
          key: "hasHeader",
          value: function hasHeader(name) {
            if (name) {
              return this._headers.hasOwnProperty(Utils.headerize(name)) && true || false;
            }
          }
        }, {
          key: "deleteHeader",
          value: function deleteHeader(header) {
            header = Utils.headerize(header);
            if (this._headers.hasOwnProperty(header)) {
              var value = this._headers[header];
              delete this._headers[header];
              return value;
            }
          }
        }, {
          key: "clearHeaders",
          value: function clearHeaders() {
            this._headers = {};
          }
        }, {
          key: "clone",
          value: function clone() {
            return new URI(this._scheme, this._user, this._host, this._port, JSON.parse(JSON.stringify(this._parameters)), JSON.parse(JSON.stringify(this._headers)));
          }
        }, {
          key: "toString",
          value: function toString() {
            var headers = [];
            var uri = "".concat(this._scheme, ":");
            if (this._user) {
              uri += "".concat(Utils.escapeUser(this._user), "@");
            }
            uri += this._host;
            if (this._port || this._port === 0) {
              uri += ":".concat(this._port);
            }
            for (var parameter in this._parameters) {
              if (Object.prototype.hasOwnProperty.call(this._parameters, parameter)) {
                uri += ";".concat(parameter);
                if (this._parameters[parameter] !== null) {
                  uri += "=".concat(this._parameters[parameter]);
                }
              }
            }
            for (var header in this._headers) {
              if (Object.prototype.hasOwnProperty.call(this._headers, header)) {
                var _iterator = _createForOfIteratorHelper(this._headers[header]), _step;
                try {
                  for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                    var item = _step.value;
                    headers.push("".concat(header, "=").concat(item));
                  }
                } catch (err) {
                  _iterator.e(err);
                } finally {
                  _iterator.f();
                }
              }
            }
            if (headers.length > 0) {
              uri += "?".concat(headers.join("&"));
            }
            return uri;
          }
        }, {
          key: "toAor",
          value: function toAor(show_port) {
            var aor = "".concat(this._scheme, ":");
            if (this._user) {
              aor += "".concat(Utils.escapeUser(this._user), "@");
            }
            aor += this._host;
            if (show_port && (this._port || this._port === 0)) {
              aor += ":".concat(this._port);
            }
            return aor;
          }
        }, {
          key: "scheme",
          get: function get() {
            return this._scheme;
          },
          set: function set(value) {
            this._scheme = value.toLowerCase();
          }
        }, {
          key: "user",
          get: function get() {
            return this._user;
          },
          set: function set(value) {
            this._user = value;
          }
        }, {
          key: "host",
          get: function get() {
            return this._host;
          },
          set: function set(value) {
            this._host = value.toLowerCase();
          }
        }, {
          key: "port",
          get: function get() {
            return this._port;
          },
          set: function set(value) {
            this._port = value === 0 ? value : parseInt(value, 10) || null;
          }
        }]);
        return URI;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Utils.js
  var require_Utils = __commonJS({
    "node_modules/jssip/lib-es5/Utils.js"(exports) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      var JsSIP_C = require_Constants();
      var URI = require_URI();
      var Grammar = require_Grammar();
      exports.str_utf8_length = function(string) {
        return unescape(encodeURIComponent(string)).length;
      };
      var isFunction = exports.isFunction = function(fn) {
        if (fn !== void 0) {
          return Object.prototype.toString.call(fn) === "[object Function]" ? true : false;
        } else {
          return false;
        }
      };
      exports.isString = function(str) {
        if (str !== void 0) {
          return Object.prototype.toString.call(str) === "[object String]" ? true : false;
        } else {
          return false;
        }
      };
      exports.isDecimal = function(num) {
        return !isNaN(num) && parseFloat(num) === parseInt(num, 10);
      };
      exports.isEmpty = function(value) {
        return value === null || value === "" || value === void 0 || Array.isArray(value) && value.length === 0 || typeof value === "number" && isNaN(value);
      };
      exports.hasMethods = function(obj) {
        for (var _len = arguments.length, methodNames = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
          methodNames[_key - 1] = arguments[_key];
        }
        for (var _i = 0, _methodNames = methodNames; _i < _methodNames.length; _i++) {
          var methodName = _methodNames[_i];
          if (isFunction(obj[methodName])) {
            return false;
          }
        }
        return true;
      };
      var createRandomToken = exports.createRandomToken = function(size) {
        var base = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : 32;
        var i, r, token = "";
        for (i = 0; i < size; i++) {
          r = Math.random() * base | 0;
          token += r.toString(base);
        }
        return token;
      };
      exports.newTag = function() {
        return createRandomToken(10);
      };
      exports.newUUID = function() {
        var UUID = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
          var r = Math.random() * 16 | 0, v = c === "x" ? r : r & 3 | 8;
          return v.toString(16);
        });
        return UUID;
      };
      exports.hostType = function(host) {
        if (!host) {
          return;
        } else {
          host = Grammar.parse(host, "host");
          if (host !== -1) {
            return host.host_type;
          }
        }
      };
      var escapeUser = exports.escapeUser = function(user) {
        return encodeURIComponent(decodeURIComponent(user)).replace(/%3A/ig, ":").replace(/%2B/ig, "+").replace(/%3F/ig, "?").replace(/%2F/ig, "/");
      };
      exports.normalizeTarget = function(target, domain) {
        if (!target) {
          return;
        } else if (target instanceof URI) {
          return target;
        } else if (typeof target === "string") {
          var target_array = target.split("@");
          var target_user;
          var target_domain;
          switch (target_array.length) {
            case 1:
              if (!domain) {
                return;
              }
              target_user = target;
              target_domain = domain;
              break;
            case 2:
              target_user = target_array[0];
              target_domain = target_array[1];
              break;
            default:
              target_user = target_array.slice(0, target_array.length - 1).join("@");
              target_domain = target_array[target_array.length - 1];
          }
          target_user = target_user.replace(/^(sips?|tel):/i, "");
          if (/^[-.()]*\+?[0-9\-.()]+$/.test(target_user)) {
            target_user = target_user.replace(/[-.()]/g, "");
          }
          target = "".concat(JsSIP_C.SIP, ":").concat(escapeUser(target_user), "@").concat(target_domain);
          var uri;
          if (uri = URI.parse(target)) {
            return uri;
          } else {
            return;
          }
        } else {
          return;
        }
      };
      exports.headerize = function(string) {
        var exceptions = {
          "Call-Id": "Call-ID",
          "Cseq": "CSeq",
          "Www-Authenticate": "WWW-Authenticate"
        };
        var name = string.toLowerCase().replace(/_/g, "-").split("-");
        var hname = "";
        var parts = name.length;
        var part;
        for (part = 0; part < parts; part++) {
          if (part !== 0) {
            hname += "-";
          }
          hname += name[part].charAt(0).toUpperCase() + name[part].substring(1);
        }
        if (exceptions[hname]) {
          hname = exceptions[hname];
        }
        return hname;
      };
      exports.sipErrorCause = function(status_code) {
        for (var cause in JsSIP_C.SIP_ERROR_CAUSES) {
          if (JsSIP_C.SIP_ERROR_CAUSES[cause].indexOf(status_code) !== -1) {
            return JsSIP_C.causes[cause];
          }
        }
        return JsSIP_C.causes.SIP_FAILURE_CODE;
      };
      exports.getRandomTestNetIP = function() {
        function getOctet(from, to) {
          return Math.floor(Math.random() * (to - from + 1) + from);
        }
        return "192.0.2.".concat(getOctet(1, 254));
      };
      exports.calculateMD5 = function(string) {
        function rotateLeft(lValue, iShiftBits) {
          return lValue << iShiftBits | lValue >>> 32 - iShiftBits;
        }
        function addUnsigned(lX, lY) {
          var lX8 = lX & 2147483648;
          var lY8 = lY & 2147483648;
          var lX4 = lX & 1073741824;
          var lY4 = lY & 1073741824;
          var lResult = (lX & 1073741823) + (lY & 1073741823);
          if (lX4 & lY4) {
            return lResult ^ 2147483648 ^ lX8 ^ lY8;
          }
          if (lX4 | lY4) {
            if (lResult & 1073741824) {
              return lResult ^ 3221225472 ^ lX8 ^ lY8;
            } else {
              return lResult ^ 1073741824 ^ lX8 ^ lY8;
            }
          } else {
            return lResult ^ lX8 ^ lY8;
          }
        }
        function doF(x2, y, z) {
          return x2 & y | ~x2 & z;
        }
        function doG(x2, y, z) {
          return x2 & z | y & ~z;
        }
        function doH(x2, y, z) {
          return x2 ^ y ^ z;
        }
        function doI(x2, y, z) {
          return y ^ (x2 | ~z);
        }
        function doFF(a2, b2, c2, d2, x2, s, ac) {
          a2 = addUnsigned(a2, addUnsigned(addUnsigned(doF(b2, c2, d2), x2), ac));
          return addUnsigned(rotateLeft(a2, s), b2);
        }
        function doGG(a2, b2, c2, d2, x2, s, ac) {
          a2 = addUnsigned(a2, addUnsigned(addUnsigned(doG(b2, c2, d2), x2), ac));
          return addUnsigned(rotateLeft(a2, s), b2);
        }
        function doHH(a2, b2, c2, d2, x2, s, ac) {
          a2 = addUnsigned(a2, addUnsigned(addUnsigned(doH(b2, c2, d2), x2), ac));
          return addUnsigned(rotateLeft(a2, s), b2);
        }
        function doII(a2, b2, c2, d2, x2, s, ac) {
          a2 = addUnsigned(a2, addUnsigned(addUnsigned(doI(b2, c2, d2), x2), ac));
          return addUnsigned(rotateLeft(a2, s), b2);
        }
        function convertToWordArray(str) {
          var lWordCount;
          var lMessageLength = str.length;
          var lNumberOfWords_temp1 = lMessageLength + 8;
          var lNumberOfWords_temp2 = (lNumberOfWords_temp1 - lNumberOfWords_temp1 % 64) / 64;
          var lNumberOfWords = (lNumberOfWords_temp2 + 1) * 16;
          var lWordArray = new Array(lNumberOfWords - 1);
          var lBytePosition = 0;
          var lByteCount = 0;
          while (lByteCount < lMessageLength) {
            lWordCount = (lByteCount - lByteCount % 4) / 4;
            lBytePosition = lByteCount % 4 * 8;
            lWordArray[lWordCount] = lWordArray[lWordCount] | str.charCodeAt(lByteCount) << lBytePosition;
            lByteCount++;
          }
          lWordCount = (lByteCount - lByteCount % 4) / 4;
          lBytePosition = lByteCount % 4 * 8;
          lWordArray[lWordCount] = lWordArray[lWordCount] | 128 << lBytePosition;
          lWordArray[lNumberOfWords - 2] = lMessageLength << 3;
          lWordArray[lNumberOfWords - 1] = lMessageLength >>> 29;
          return lWordArray;
        }
        function wordToHex(lValue) {
          var wordToHexValue = "", wordToHexValue_temp = "", lByte, lCount;
          for (lCount = 0; lCount <= 3; lCount++) {
            lByte = lValue >>> lCount * 8 & 255;
            wordToHexValue_temp = "0".concat(lByte.toString(16));
            wordToHexValue = wordToHexValue + wordToHexValue_temp.substr(wordToHexValue_temp.length - 2, 2);
          }
          return wordToHexValue;
        }
        function utf8Encode(str) {
          var utftext = "";
          for (var n = 0; n < str.length; n++) {
            var _c = str.charCodeAt(n);
            if (_c < 128) {
              utftext += String.fromCharCode(_c);
            } else if (_c > 127 && _c < 2048) {
              utftext += String.fromCharCode(_c >> 6 | 192);
              utftext += String.fromCharCode(_c & 63 | 128);
            } else {
              utftext += String.fromCharCode(_c >> 12 | 224);
              utftext += String.fromCharCode(_c >> 6 & 63 | 128);
              utftext += String.fromCharCode(_c & 63 | 128);
            }
          }
          return utftext;
        }
        var x = [];
        var k, AA, BB, CC, DD, a, b, c, d;
        var S11 = 7, S12 = 12, S13 = 17, S14 = 22;
        var S21 = 5, S22 = 9, S23 = 14, S24 = 20;
        var S31 = 4, S32 = 11, S33 = 16, S34 = 23;
        var S41 = 6, S42 = 10, S43 = 15, S44 = 21;
        string = utf8Encode(string);
        x = convertToWordArray(string);
        a = 1732584193;
        b = 4023233417;
        c = 2562383102;
        d = 271733878;
        for (k = 0; k < x.length; k += 16) {
          AA = a;
          BB = b;
          CC = c;
          DD = d;
          a = doFF(a, b, c, d, x[k + 0], S11, 3614090360);
          d = doFF(d, a, b, c, x[k + 1], S12, 3905402710);
          c = doFF(c, d, a, b, x[k + 2], S13, 606105819);
          b = doFF(b, c, d, a, x[k + 3], S14, 3250441966);
          a = doFF(a, b, c, d, x[k + 4], S11, 4118548399);
          d = doFF(d, a, b, c, x[k + 5], S12, 1200080426);
          c = doFF(c, d, a, b, x[k + 6], S13, 2821735955);
          b = doFF(b, c, d, a, x[k + 7], S14, 4249261313);
          a = doFF(a, b, c, d, x[k + 8], S11, 1770035416);
          d = doFF(d, a, b, c, x[k + 9], S12, 2336552879);
          c = doFF(c, d, a, b, x[k + 10], S13, 4294925233);
          b = doFF(b, c, d, a, x[k + 11], S14, 2304563134);
          a = doFF(a, b, c, d, x[k + 12], S11, 1804603682);
          d = doFF(d, a, b, c, x[k + 13], S12, 4254626195);
          c = doFF(c, d, a, b, x[k + 14], S13, 2792965006);
          b = doFF(b, c, d, a, x[k + 15], S14, 1236535329);
          a = doGG(a, b, c, d, x[k + 1], S21, 4129170786);
          d = doGG(d, a, b, c, x[k + 6], S22, 3225465664);
          c = doGG(c, d, a, b, x[k + 11], S23, 643717713);
          b = doGG(b, c, d, a, x[k + 0], S24, 3921069994);
          a = doGG(a, b, c, d, x[k + 5], S21, 3593408605);
          d = doGG(d, a, b, c, x[k + 10], S22, 38016083);
          c = doGG(c, d, a, b, x[k + 15], S23, 3634488961);
          b = doGG(b, c, d, a, x[k + 4], S24, 3889429448);
          a = doGG(a, b, c, d, x[k + 9], S21, 568446438);
          d = doGG(d, a, b, c, x[k + 14], S22, 3275163606);
          c = doGG(c, d, a, b, x[k + 3], S23, 4107603335);
          b = doGG(b, c, d, a, x[k + 8], S24, 1163531501);
          a = doGG(a, b, c, d, x[k + 13], S21, 2850285829);
          d = doGG(d, a, b, c, x[k + 2], S22, 4243563512);
          c = doGG(c, d, a, b, x[k + 7], S23, 1735328473);
          b = doGG(b, c, d, a, x[k + 12], S24, 2368359562);
          a = doHH(a, b, c, d, x[k + 5], S31, 4294588738);
          d = doHH(d, a, b, c, x[k + 8], S32, 2272392833);
          c = doHH(c, d, a, b, x[k + 11], S33, 1839030562);
          b = doHH(b, c, d, a, x[k + 14], S34, 4259657740);
          a = doHH(a, b, c, d, x[k + 1], S31, 2763975236);
          d = doHH(d, a, b, c, x[k + 4], S32, 1272893353);
          c = doHH(c, d, a, b, x[k + 7], S33, 4139469664);
          b = doHH(b, c, d, a, x[k + 10], S34, 3200236656);
          a = doHH(a, b, c, d, x[k + 13], S31, 681279174);
          d = doHH(d, a, b, c, x[k + 0], S32, 3936430074);
          c = doHH(c, d, a, b, x[k + 3], S33, 3572445317);
          b = doHH(b, c, d, a, x[k + 6], S34, 76029189);
          a = doHH(a, b, c, d, x[k + 9], S31, 3654602809);
          d = doHH(d, a, b, c, x[k + 12], S32, 3873151461);
          c = doHH(c, d, a, b, x[k + 15], S33, 530742520);
          b = doHH(b, c, d, a, x[k + 2], S34, 3299628645);
          a = doII(a, b, c, d, x[k + 0], S41, 4096336452);
          d = doII(d, a, b, c, x[k + 7], S42, 1126891415);
          c = doII(c, d, a, b, x[k + 14], S43, 2878612391);
          b = doII(b, c, d, a, x[k + 5], S44, 4237533241);
          a = doII(a, b, c, d, x[k + 12], S41, 1700485571);
          d = doII(d, a, b, c, x[k + 3], S42, 2399980690);
          c = doII(c, d, a, b, x[k + 10], S43, 4293915773);
          b = doII(b, c, d, a, x[k + 1], S44, 2240044497);
          a = doII(a, b, c, d, x[k + 8], S41, 1873313359);
          d = doII(d, a, b, c, x[k + 15], S42, 4264355552);
          c = doII(c, d, a, b, x[k + 6], S43, 2734768916);
          b = doII(b, c, d, a, x[k + 13], S44, 1309151649);
          a = doII(a, b, c, d, x[k + 4], S41, 4149444226);
          d = doII(d, a, b, c, x[k + 11], S42, 3174756917);
          c = doII(c, d, a, b, x[k + 2], S43, 718787259);
          b = doII(b, c, d, a, x[k + 9], S44, 3951481745);
          a = addUnsigned(a, AA);
          b = addUnsigned(b, BB);
          c = addUnsigned(c, CC);
          d = addUnsigned(d, DD);
        }
        var temp = wordToHex(a) + wordToHex(b) + wordToHex(c) + wordToHex(d);
        return temp.toLowerCase();
      };
      exports.closeMediaStream = function(stream) {
        if (!stream) {
          return;
        }
        try {
          var tracks;
          if (stream.getTracks) {
            tracks = stream.getTracks();
            var _iterator = _createForOfIteratorHelper(tracks), _step;
            try {
              for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                var track = _step.value;
                track.stop();
              }
            } catch (err) {
              _iterator.e(err);
            } finally {
              _iterator.f();
            }
          } else {
            tracks = stream.getAudioTracks();
            var _iterator2 = _createForOfIteratorHelper(tracks), _step2;
            try {
              for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
                var _track = _step2.value;
                _track.stop();
              }
            } catch (err) {
              _iterator2.e(err);
            } finally {
              _iterator2.f();
            }
            tracks = stream.getVideoTracks();
            var _iterator3 = _createForOfIteratorHelper(tracks), _step3;
            try {
              for (_iterator3.s(); !(_step3 = _iterator3.n()).done; ) {
                var _track2 = _step3.value;
                _track2.stop();
              }
            } catch (err) {
              _iterator3.e(err);
            } finally {
              _iterator3.f();
            }
          }
        } catch (error) {
          if (typeof stream.stop === "function" || _typeof(stream.stop) === "object") {
            stream.stop();
          }
        }
      };
      exports.cloneArray = function(array) {
        return array && array.slice() || [];
      };
      exports.cloneObject = function(obj) {
        var fallback = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
        return obj && Object.assign({}, obj) || fallback;
      };
    }
  });

  // node_modules/events/events.js
  var require_events = __commonJS({
    "node_modules/events/events.js"(exports, module) {
      "use strict";
      var R = typeof Reflect === "object" ? Reflect : null;
      var ReflectApply = R && typeof R.apply === "function" ? R.apply : function ReflectApply2(target, receiver, args) {
        return Function.prototype.apply.call(target, receiver, args);
      };
      var ReflectOwnKeys;
      if (R && typeof R.ownKeys === "function") {
        ReflectOwnKeys = R.ownKeys;
      } else if (Object.getOwnPropertySymbols) {
        ReflectOwnKeys = function ReflectOwnKeys2(target) {
          return Object.getOwnPropertyNames(target).concat(Object.getOwnPropertySymbols(target));
        };
      } else {
        ReflectOwnKeys = function ReflectOwnKeys2(target) {
          return Object.getOwnPropertyNames(target);
        };
      }
      function ProcessEmitWarning(warning) {
        if (console && console.warn) console.warn(warning);
      }
      var NumberIsNaN = Number.isNaN || function NumberIsNaN2(value) {
        return value !== value;
      };
      function EventEmitter() {
        EventEmitter.init.call(this);
      }
      module.exports = EventEmitter;
      module.exports.once = once;
      EventEmitter.EventEmitter = EventEmitter;
      EventEmitter.prototype._events = void 0;
      EventEmitter.prototype._eventsCount = 0;
      EventEmitter.prototype._maxListeners = void 0;
      var defaultMaxListeners = 10;
      function checkListener(listener) {
        if (typeof listener !== "function") {
          throw new TypeError('The "listener" argument must be of type Function. Received type ' + typeof listener);
        }
      }
      Object.defineProperty(EventEmitter, "defaultMaxListeners", {
        enumerable: true,
        get: function() {
          return defaultMaxListeners;
        },
        set: function(arg) {
          if (typeof arg !== "number" || arg < 0 || NumberIsNaN(arg)) {
            throw new RangeError('The value of "defaultMaxListeners" is out of range. It must be a non-negative number. Received ' + arg + ".");
          }
          defaultMaxListeners = arg;
        }
      });
      EventEmitter.init = function() {
        if (this._events === void 0 || this._events === Object.getPrototypeOf(this)._events) {
          this._events = /* @__PURE__ */ Object.create(null);
          this._eventsCount = 0;
        }
        this._maxListeners = this._maxListeners || void 0;
      };
      EventEmitter.prototype.setMaxListeners = function setMaxListeners(n) {
        if (typeof n !== "number" || n < 0 || NumberIsNaN(n)) {
          throw new RangeError('The value of "n" is out of range. It must be a non-negative number. Received ' + n + ".");
        }
        this._maxListeners = n;
        return this;
      };
      function _getMaxListeners(that) {
        if (that._maxListeners === void 0)
          return EventEmitter.defaultMaxListeners;
        return that._maxListeners;
      }
      EventEmitter.prototype.getMaxListeners = function getMaxListeners() {
        return _getMaxListeners(this);
      };
      EventEmitter.prototype.emit = function emit(type) {
        var args = [];
        for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
        var doError = type === "error";
        var events = this._events;
        if (events !== void 0)
          doError = doError && events.error === void 0;
        else if (!doError)
          return false;
        if (doError) {
          var er;
          if (args.length > 0)
            er = args[0];
          if (er instanceof Error) {
            throw er;
          }
          var err = new Error("Unhandled error." + (er ? " (" + er.message + ")" : ""));
          err.context = er;
          throw err;
        }
        var handler = events[type];
        if (handler === void 0)
          return false;
        if (typeof handler === "function") {
          ReflectApply(handler, this, args);
        } else {
          var len = handler.length;
          var listeners = arrayClone(handler, len);
          for (var i = 0; i < len; ++i)
            ReflectApply(listeners[i], this, args);
        }
        return true;
      };
      function _addListener(target, type, listener, prepend) {
        var m;
        var events;
        var existing;
        checkListener(listener);
        events = target._events;
        if (events === void 0) {
          events = target._events = /* @__PURE__ */ Object.create(null);
          target._eventsCount = 0;
        } else {
          if (events.newListener !== void 0) {
            target.emit(
              "newListener",
              type,
              listener.listener ? listener.listener : listener
            );
            events = target._events;
          }
          existing = events[type];
        }
        if (existing === void 0) {
          existing = events[type] = listener;
          ++target._eventsCount;
        } else {
          if (typeof existing === "function") {
            existing = events[type] = prepend ? [listener, existing] : [existing, listener];
          } else if (prepend) {
            existing.unshift(listener);
          } else {
            existing.push(listener);
          }
          m = _getMaxListeners(target);
          if (m > 0 && existing.length > m && !existing.warned) {
            existing.warned = true;
            var w = new Error("Possible EventEmitter memory leak detected. " + existing.length + " " + String(type) + " listeners added. Use emitter.setMaxListeners() to increase limit");
            w.name = "MaxListenersExceededWarning";
            w.emitter = target;
            w.type = type;
            w.count = existing.length;
            ProcessEmitWarning(w);
          }
        }
        return target;
      }
      EventEmitter.prototype.addListener = function addListener(type, listener) {
        return _addListener(this, type, listener, false);
      };
      EventEmitter.prototype.on = EventEmitter.prototype.addListener;
      EventEmitter.prototype.prependListener = function prependListener(type, listener) {
        return _addListener(this, type, listener, true);
      };
      function onceWrapper() {
        if (!this.fired) {
          this.target.removeListener(this.type, this.wrapFn);
          this.fired = true;
          if (arguments.length === 0)
            return this.listener.call(this.target);
          return this.listener.apply(this.target, arguments);
        }
      }
      function _onceWrap(target, type, listener) {
        var state = { fired: false, wrapFn: void 0, target, type, listener };
        var wrapped = onceWrapper.bind(state);
        wrapped.listener = listener;
        state.wrapFn = wrapped;
        return wrapped;
      }
      EventEmitter.prototype.once = function once2(type, listener) {
        checkListener(listener);
        this.on(type, _onceWrap(this, type, listener));
        return this;
      };
      EventEmitter.prototype.prependOnceListener = function prependOnceListener(type, listener) {
        checkListener(listener);
        this.prependListener(type, _onceWrap(this, type, listener));
        return this;
      };
      EventEmitter.prototype.removeListener = function removeListener(type, listener) {
        var list, events, position, i, originalListener;
        checkListener(listener);
        events = this._events;
        if (events === void 0)
          return this;
        list = events[type];
        if (list === void 0)
          return this;
        if (list === listener || list.listener === listener) {
          if (--this._eventsCount === 0)
            this._events = /* @__PURE__ */ Object.create(null);
          else {
            delete events[type];
            if (events.removeListener)
              this.emit("removeListener", type, list.listener || listener);
          }
        } else if (typeof list !== "function") {
          position = -1;
          for (i = list.length - 1; i >= 0; i--) {
            if (list[i] === listener || list[i].listener === listener) {
              originalListener = list[i].listener;
              position = i;
              break;
            }
          }
          if (position < 0)
            return this;
          if (position === 0)
            list.shift();
          else {
            spliceOne(list, position);
          }
          if (list.length === 1)
            events[type] = list[0];
          if (events.removeListener !== void 0)
            this.emit("removeListener", type, originalListener || listener);
        }
        return this;
      };
      EventEmitter.prototype.off = EventEmitter.prototype.removeListener;
      EventEmitter.prototype.removeAllListeners = function removeAllListeners(type) {
        var listeners, events, i;
        events = this._events;
        if (events === void 0)
          return this;
        if (events.removeListener === void 0) {
          if (arguments.length === 0) {
            this._events = /* @__PURE__ */ Object.create(null);
            this._eventsCount = 0;
          } else if (events[type] !== void 0) {
            if (--this._eventsCount === 0)
              this._events = /* @__PURE__ */ Object.create(null);
            else
              delete events[type];
          }
          return this;
        }
        if (arguments.length === 0) {
          var keys = Object.keys(events);
          var key;
          for (i = 0; i < keys.length; ++i) {
            key = keys[i];
            if (key === "removeListener") continue;
            this.removeAllListeners(key);
          }
          this.removeAllListeners("removeListener");
          this._events = /* @__PURE__ */ Object.create(null);
          this._eventsCount = 0;
          return this;
        }
        listeners = events[type];
        if (typeof listeners === "function") {
          this.removeListener(type, listeners);
        } else if (listeners !== void 0) {
          for (i = listeners.length - 1; i >= 0; i--) {
            this.removeListener(type, listeners[i]);
          }
        }
        return this;
      };
      function _listeners(target, type, unwrap) {
        var events = target._events;
        if (events === void 0)
          return [];
        var evlistener = events[type];
        if (evlistener === void 0)
          return [];
        if (typeof evlistener === "function")
          return unwrap ? [evlistener.listener || evlistener] : [evlistener];
        return unwrap ? unwrapListeners(evlistener) : arrayClone(evlistener, evlistener.length);
      }
      EventEmitter.prototype.listeners = function listeners(type) {
        return _listeners(this, type, true);
      };
      EventEmitter.prototype.rawListeners = function rawListeners(type) {
        return _listeners(this, type, false);
      };
      EventEmitter.listenerCount = function(emitter, type) {
        if (typeof emitter.listenerCount === "function") {
          return emitter.listenerCount(type);
        } else {
          return listenerCount.call(emitter, type);
        }
      };
      EventEmitter.prototype.listenerCount = listenerCount;
      function listenerCount(type) {
        var events = this._events;
        if (events !== void 0) {
          var evlistener = events[type];
          if (typeof evlistener === "function") {
            return 1;
          } else if (evlistener !== void 0) {
            return evlistener.length;
          }
        }
        return 0;
      }
      EventEmitter.prototype.eventNames = function eventNames() {
        return this._eventsCount > 0 ? ReflectOwnKeys(this._events) : [];
      };
      function arrayClone(arr, n) {
        var copy = new Array(n);
        for (var i = 0; i < n; ++i)
          copy[i] = arr[i];
        return copy;
      }
      function spliceOne(list, index) {
        for (; index + 1 < list.length; index++)
          list[index] = list[index + 1];
        list.pop();
      }
      function unwrapListeners(arr) {
        var ret = new Array(arr.length);
        for (var i = 0; i < ret.length; ++i) {
          ret[i] = arr[i].listener || arr[i];
        }
        return ret;
      }
      function once(emitter, name) {
        return new Promise(function(resolve, reject) {
          function errorListener(err) {
            emitter.removeListener(name, resolver);
            reject(err);
          }
          function resolver() {
            if (typeof emitter.removeListener === "function") {
              emitter.removeListener("error", errorListener);
            }
            resolve([].slice.call(arguments));
          }
          ;
          eventTargetAgnosticAddListener(emitter, name, resolver, { once: true });
          if (name !== "error") {
            addErrorHandlerIfEventEmitter(emitter, errorListener, { once: true });
          }
        });
      }
      function addErrorHandlerIfEventEmitter(emitter, handler, flags) {
        if (typeof emitter.on === "function") {
          eventTargetAgnosticAddListener(emitter, "error", handler, flags);
        }
      }
      function eventTargetAgnosticAddListener(emitter, name, listener, flags) {
        if (typeof emitter.on === "function") {
          if (flags.once) {
            emitter.once(name, listener);
          } else {
            emitter.on(name, listener);
          }
        } else if (typeof emitter.addEventListener === "function") {
          emitter.addEventListener(name, function wrapListener(arg) {
            if (flags.once) {
              emitter.removeEventListener(name, wrapListener);
            }
            listener(arg);
          });
        } else {
          throw new TypeError('The "emitter" argument must be of type EventEmitter. Received type ' + typeof emitter);
        }
      }
    }
  });

  // node_modules/ms/index.js
  var require_ms = __commonJS({
    "node_modules/ms/index.js"(exports, module) {
      var s = 1e3;
      var m = s * 60;
      var h = m * 60;
      var d = h * 24;
      var w = d * 7;
      var y = d * 365.25;
      module.exports = function(val, options) {
        options = options || {};
        var type = typeof val;
        if (type === "string" && val.length > 0) {
          return parse(val);
        } else if (type === "number" && isFinite(val)) {
          return options.long ? fmtLong(val) : fmtShort(val);
        }
        throw new Error(
          "val is not a non-empty string or a valid number. val=" + JSON.stringify(val)
        );
      };
      function parse(str) {
        str = String(str);
        if (str.length > 100) {
          return;
        }
        var match = /^(-?(?:\d+)?\.?\d+) *(milliseconds?|msecs?|ms|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w|years?|yrs?|y)?$/i.exec(
          str
        );
        if (!match) {
          return;
        }
        var n = parseFloat(match[1]);
        var type = (match[2] || "ms").toLowerCase();
        switch (type) {
          case "years":
          case "year":
          case "yrs":
          case "yr":
          case "y":
            return n * y;
          case "weeks":
          case "week":
          case "w":
            return n * w;
          case "days":
          case "day":
          case "d":
            return n * d;
          case "hours":
          case "hour":
          case "hrs":
          case "hr":
          case "h":
            return n * h;
          case "minutes":
          case "minute":
          case "mins":
          case "min":
          case "m":
            return n * m;
          case "seconds":
          case "second":
          case "secs":
          case "sec":
          case "s":
            return n * s;
          case "milliseconds":
          case "millisecond":
          case "msecs":
          case "msec":
          case "ms":
            return n;
          default:
            return void 0;
        }
      }
      function fmtShort(ms) {
        var msAbs = Math.abs(ms);
        if (msAbs >= d) {
          return Math.round(ms / d) + "d";
        }
        if (msAbs >= h) {
          return Math.round(ms / h) + "h";
        }
        if (msAbs >= m) {
          return Math.round(ms / m) + "m";
        }
        if (msAbs >= s) {
          return Math.round(ms / s) + "s";
        }
        return ms + "ms";
      }
      function fmtLong(ms) {
        var msAbs = Math.abs(ms);
        if (msAbs >= d) {
          return plural(ms, msAbs, d, "day");
        }
        if (msAbs >= h) {
          return plural(ms, msAbs, h, "hour");
        }
        if (msAbs >= m) {
          return plural(ms, msAbs, m, "minute");
        }
        if (msAbs >= s) {
          return plural(ms, msAbs, s, "second");
        }
        return ms + " ms";
      }
      function plural(ms, msAbs, n, name) {
        var isPlural = msAbs >= n * 1.5;
        return Math.round(ms / n) + " " + name + (isPlural ? "s" : "");
      }
    }
  });

  // node_modules/debug/src/common.js
  var require_common = __commonJS({
    "node_modules/debug/src/common.js"(exports, module) {
      function setup(env) {
        createDebug.debug = createDebug;
        createDebug.default = createDebug;
        createDebug.coerce = coerce;
        createDebug.disable = disable;
        createDebug.enable = enable;
        createDebug.enabled = enabled;
        createDebug.humanize = require_ms();
        createDebug.destroy = destroy;
        Object.keys(env).forEach((key) => {
          createDebug[key] = env[key];
        });
        createDebug.names = [];
        createDebug.skips = [];
        createDebug.formatters = {};
        function selectColor(namespace) {
          let hash = 0;
          for (let i = 0; i < namespace.length; i++) {
            hash = (hash << 5) - hash + namespace.charCodeAt(i);
            hash |= 0;
          }
          return createDebug.colors[Math.abs(hash) % createDebug.colors.length];
        }
        createDebug.selectColor = selectColor;
        function createDebug(namespace) {
          let prevTime;
          let enableOverride = null;
          let namespacesCache;
          let enabledCache;
          function debug(...args) {
            if (!debug.enabled) {
              return;
            }
            const self = debug;
            const curr = Number(/* @__PURE__ */ new Date());
            const ms = curr - (prevTime || curr);
            self.diff = ms;
            self.prev = prevTime;
            self.curr = curr;
            prevTime = curr;
            args[0] = createDebug.coerce(args[0]);
            if (typeof args[0] !== "string") {
              args.unshift("%O");
            }
            let index = 0;
            args[0] = args[0].replace(/%([a-zA-Z%])/g, (match, format) => {
              if (match === "%%") {
                return "%";
              }
              index++;
              const formatter = createDebug.formatters[format];
              if (typeof formatter === "function") {
                const val = args[index];
                match = formatter.call(self, val);
                args.splice(index, 1);
                index--;
              }
              return match;
            });
            createDebug.formatArgs.call(self, args);
            const logFn = self.log || createDebug.log;
            logFn.apply(self, args);
          }
          debug.namespace = namespace;
          debug.useColors = createDebug.useColors();
          debug.color = createDebug.selectColor(namespace);
          debug.extend = extend;
          debug.destroy = createDebug.destroy;
          Object.defineProperty(debug, "enabled", {
            enumerable: true,
            configurable: false,
            get: () => {
              if (enableOverride !== null) {
                return enableOverride;
              }
              if (namespacesCache !== createDebug.namespaces) {
                namespacesCache = createDebug.namespaces;
                enabledCache = createDebug.enabled(namespace);
              }
              return enabledCache;
            },
            set: (v) => {
              enableOverride = v;
            }
          });
          if (typeof createDebug.init === "function") {
            createDebug.init(debug);
          }
          return debug;
        }
        function extend(namespace, delimiter) {
          const newDebug = createDebug(this.namespace + (typeof delimiter === "undefined" ? ":" : delimiter) + namespace);
          newDebug.log = this.log;
          return newDebug;
        }
        function enable(namespaces) {
          createDebug.save(namespaces);
          createDebug.namespaces = namespaces;
          createDebug.names = [];
          createDebug.skips = [];
          const split = (typeof namespaces === "string" ? namespaces : "").trim().replace(/\s+/g, ",").split(",").filter(Boolean);
          for (const ns of split) {
            if (ns[0] === "-") {
              createDebug.skips.push(ns.slice(1));
            } else {
              createDebug.names.push(ns);
            }
          }
        }
        function matchesTemplate(search, template) {
          let searchIndex = 0;
          let templateIndex = 0;
          let starIndex = -1;
          let matchIndex = 0;
          while (searchIndex < search.length) {
            if (templateIndex < template.length && (template[templateIndex] === search[searchIndex] || template[templateIndex] === "*")) {
              if (template[templateIndex] === "*") {
                starIndex = templateIndex;
                matchIndex = searchIndex;
                templateIndex++;
              } else {
                searchIndex++;
                templateIndex++;
              }
            } else if (starIndex !== -1) {
              templateIndex = starIndex + 1;
              matchIndex++;
              searchIndex = matchIndex;
            } else {
              return false;
            }
          }
          while (templateIndex < template.length && template[templateIndex] === "*") {
            templateIndex++;
          }
          return templateIndex === template.length;
        }
        function disable() {
          const namespaces = [
            ...createDebug.names,
            ...createDebug.skips.map((namespace) => "-" + namespace)
          ].join(",");
          createDebug.enable("");
          return namespaces;
        }
        function enabled(name) {
          for (const skip of createDebug.skips) {
            if (matchesTemplate(name, skip)) {
              return false;
            }
          }
          for (const ns of createDebug.names) {
            if (matchesTemplate(name, ns)) {
              return true;
            }
          }
          return false;
        }
        function coerce(val) {
          if (val instanceof Error) {
            return val.stack || val.message;
          }
          return val;
        }
        function destroy() {
          console.warn("Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.");
        }
        createDebug.enable(createDebug.load());
        return createDebug;
      }
      module.exports = setup;
    }
  });

  // node_modules/debug/src/browser.js
  var require_browser = __commonJS({
    "node_modules/debug/src/browser.js"(exports, module) {
      exports.formatArgs = formatArgs;
      exports.save = save;
      exports.load = load;
      exports.useColors = useColors;
      exports.storage = localstorage();
      exports.destroy = /* @__PURE__ */ (() => {
        let warned = false;
        return () => {
          if (!warned) {
            warned = true;
            console.warn("Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.");
          }
        };
      })();
      exports.colors = [
        "#0000CC",
        "#0000FF",
        "#0033CC",
        "#0033FF",
        "#0066CC",
        "#0066FF",
        "#0099CC",
        "#0099FF",
        "#00CC00",
        "#00CC33",
        "#00CC66",
        "#00CC99",
        "#00CCCC",
        "#00CCFF",
        "#3300CC",
        "#3300FF",
        "#3333CC",
        "#3333FF",
        "#3366CC",
        "#3366FF",
        "#3399CC",
        "#3399FF",
        "#33CC00",
        "#33CC33",
        "#33CC66",
        "#33CC99",
        "#33CCCC",
        "#33CCFF",
        "#6600CC",
        "#6600FF",
        "#6633CC",
        "#6633FF",
        "#66CC00",
        "#66CC33",
        "#9900CC",
        "#9900FF",
        "#9933CC",
        "#9933FF",
        "#99CC00",
        "#99CC33",
        "#CC0000",
        "#CC0033",
        "#CC0066",
        "#CC0099",
        "#CC00CC",
        "#CC00FF",
        "#CC3300",
        "#CC3333",
        "#CC3366",
        "#CC3399",
        "#CC33CC",
        "#CC33FF",
        "#CC6600",
        "#CC6633",
        "#CC9900",
        "#CC9933",
        "#CCCC00",
        "#CCCC33",
        "#FF0000",
        "#FF0033",
        "#FF0066",
        "#FF0099",
        "#FF00CC",
        "#FF00FF",
        "#FF3300",
        "#FF3333",
        "#FF3366",
        "#FF3399",
        "#FF33CC",
        "#FF33FF",
        "#FF6600",
        "#FF6633",
        "#FF9900",
        "#FF9933",
        "#FFCC00",
        "#FFCC33"
      ];
      function useColors() {
        if (typeof window !== "undefined" && window.process && (window.process.type === "renderer" || window.process.__nwjs)) {
          return true;
        }
        if (typeof navigator !== "undefined" && navigator.userAgent && navigator.userAgent.toLowerCase().match(/(edge|trident)\/(\d+)/)) {
          return false;
        }
        let m;
        return typeof document !== "undefined" && document.documentElement && document.documentElement.style && document.documentElement.style.WebkitAppearance || // Is firebug? http://stackoverflow.com/a/398120/376773
        typeof window !== "undefined" && window.console && (window.console.firebug || window.console.exception && window.console.table) || // Is firefox >= v31?
        // https://developer.mozilla.org/en-US/docs/Tools/Web_Console#Styling_messages
        typeof navigator !== "undefined" && navigator.userAgent && (m = navigator.userAgent.toLowerCase().match(/firefox\/(\d+)/)) && parseInt(m[1], 10) >= 31 || // Double check webkit in userAgent just in case we are in a worker
        typeof navigator !== "undefined" && navigator.userAgent && navigator.userAgent.toLowerCase().match(/applewebkit\/(\d+)/);
      }
      function formatArgs(args) {
        args[0] = (this.useColors ? "%c" : "") + this.namespace + (this.useColors ? " %c" : " ") + args[0] + (this.useColors ? "%c " : " ") + "+" + module.exports.humanize(this.diff);
        if (!this.useColors) {
          return;
        }
        const c = "color: " + this.color;
        args.splice(1, 0, c, "color: inherit");
        let index = 0;
        let lastC = 0;
        args[0].replace(/%[a-zA-Z%]/g, (match) => {
          if (match === "%%") {
            return;
          }
          index++;
          if (match === "%c") {
            lastC = index;
          }
        });
        args.splice(lastC, 0, c);
      }
      exports.log = console.debug || console.log || (() => {
      });
      function save(namespaces) {
        try {
          if (namespaces) {
            exports.storage.setItem("debug", namespaces);
          } else {
            exports.storage.removeItem("debug");
          }
        } catch (error) {
        }
      }
      function load() {
        let r;
        try {
          r = exports.storage.getItem("debug") || exports.storage.getItem("DEBUG");
        } catch (error) {
        }
        if (!r && typeof process !== "undefined" && "env" in process) {
          r = process.env.DEBUG;
        }
        return r;
      }
      function localstorage() {
        try {
          return localStorage;
        } catch (error) {
        }
      }
      module.exports = require_common()(exports);
      var { formatters } = module.exports;
      formatters.j = function(v) {
        try {
          return JSON.stringify(v);
        } catch (error) {
          return "[UnexpectedJSONParseError]: " + error.message;
        }
      };
    }
  });

  // node_modules/jssip/lib-es5/Logger.js
  var require_Logger = __commonJS({
    "node_modules/jssip/lib-es5/Logger.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var debug = require_browser();
      var APP_NAME = "JsSIP";
      module.exports = /* @__PURE__ */ function() {
        function Logger(prefix) {
          _classCallCheck(this, Logger);
          if (prefix) {
            this._debug = debug["default"]("".concat(APP_NAME, ":").concat(prefix));
            this._warn = debug["default"]("".concat(APP_NAME, ":WARN:").concat(prefix));
            this._error = debug["default"]("".concat(APP_NAME, ":ERROR:").concat(prefix));
          } else {
            this._debug = debug["default"](APP_NAME);
            this._warn = debug["default"]("".concat(APP_NAME, ":WARN"));
            this._error = debug["default"]("".concat(APP_NAME, ":ERROR"));
          }
          this._debug.log = console.info.bind(console);
          this._warn.log = console.warn.bind(console);
          this._error.log = console.error.bind(console);
        }
        _createClass(Logger, [{
          key: "debug",
          get: function get() {
            return this._debug;
          }
        }, {
          key: "warn",
          get: function get() {
            return this._warn;
          }
        }, {
          key: "error",
          get: function get() {
            return this._error;
          }
        }]);
        return Logger;
      }();
    }
  });

  // node_modules/sdp-transform/lib/grammar.js
  var require_grammar = __commonJS({
    "node_modules/sdp-transform/lib/grammar.js"(exports, module) {
      var grammar = module.exports = {
        v: [{
          name: "version",
          reg: /^(\d*)$/
        }],
        o: [{
          // o=- 20518 0 IN IP4 203.0.113.1
          // NB: sessionId will be a String in most cases because it is huge
          name: "origin",
          reg: /^(\S*) (\d*) (\d*) (\S*) IP(\d) (\S*)/,
          names: ["username", "sessionId", "sessionVersion", "netType", "ipVer", "address"],
          format: "%s %s %d %s IP%d %s"
        }],
        // default parsing of these only (though some of these feel outdated)
        s: [{ name: "name" }],
        i: [{ name: "description" }],
        u: [{ name: "uri" }],
        e: [{ name: "email" }],
        p: [{ name: "phone" }],
        z: [{ name: "timezones" }],
        // TODO: this one can actually be parsed properly...
        r: [{ name: "repeats" }],
        // TODO: this one can also be parsed properly
        // k: [{}], // outdated thing ignored
        t: [{
          // t=0 0
          name: "timing",
          reg: /^(\d*) (\d*)/,
          names: ["start", "stop"],
          format: "%d %d"
        }],
        c: [{
          // c=IN IP4 10.47.197.26
          name: "connection",
          reg: /^IN IP(\d) (\S*)/,
          names: ["version", "ip"],
          format: "IN IP%d %s"
        }],
        b: [{
          // b=AS:4000
          push: "bandwidth",
          reg: /^(TIAS|AS|CT|RR|RS):(\d*)/,
          names: ["type", "limit"],
          format: "%s:%s"
        }],
        m: [{
          // m=video 51744 RTP/AVP 126 97 98 34 31
          // NB: special - pushes to session
          // TODO: rtp/fmtp should be filtered by the payloads found here?
          reg: /^(\w*) (\d*) ([\w/]*)(?: (.*))?/,
          names: ["type", "port", "protocol", "payloads"],
          format: "%s %d %s %s"
        }],
        a: [
          {
            // a=rtpmap:110 opus/48000/2
            push: "rtp",
            reg: /^rtpmap:(\d*) ([\w\-.]*)(?:\s*\/(\d*)(?:\s*\/(\S*))?)?/,
            names: ["payload", "codec", "rate", "encoding"],
            format: function(o) {
              return o.encoding ? "rtpmap:%d %s/%s/%s" : o.rate ? "rtpmap:%d %s/%s" : "rtpmap:%d %s";
            }
          },
          {
            // a=fmtp:108 profile-level-id=24;object=23;bitrate=64000
            // a=fmtp:111 minptime=10; useinbandfec=1
            push: "fmtp",
            reg: /^fmtp:(\d*) ([\S| ]*)/,
            names: ["payload", "config"],
            format: "fmtp:%d %s"
          },
          {
            // a=control:streamid=0
            name: "control",
            reg: /^control:(.*)/,
            format: "control:%s"
          },
          {
            // a=rtcp:65179 IN IP4 193.84.77.194
            name: "rtcp",
            reg: /^rtcp:(\d*)(?: (\S*) IP(\d) (\S*))?/,
            names: ["port", "netType", "ipVer", "address"],
            format: function(o) {
              return o.address != null ? "rtcp:%d %s IP%d %s" : "rtcp:%d";
            }
          },
          {
            // a=rtcp-fb:98 trr-int 100
            push: "rtcpFbTrrInt",
            reg: /^rtcp-fb:(\*|\d*) trr-int (\d*)/,
            names: ["payload", "value"],
            format: "rtcp-fb:%s trr-int %d"
          },
          {
            // a=rtcp-fb:98 nack rpsi
            push: "rtcpFb",
            reg: /^rtcp-fb:(\*|\d*) ([\w-_]*)(?: ([\w-_]*))?/,
            names: ["payload", "type", "subtype"],
            format: function(o) {
              return o.subtype != null ? "rtcp-fb:%s %s %s" : "rtcp-fb:%s %s";
            }
          },
          {
            // a=extmap:2 urn:ietf:params:rtp-hdrext:toffset
            // a=extmap:1/recvonly URI-gps-string
            // a=extmap:3 urn:ietf:params:rtp-hdrext:encrypt urn:ietf:params:rtp-hdrext:smpte-tc 25@600/24
            push: "ext",
            reg: /^extmap:(\d+)(?:\/(\w+))?(?: (urn:ietf:params:rtp-hdrext:encrypt))? (\S*)(?: (\S*))?/,
            names: ["value", "direction", "encrypt-uri", "uri", "config"],
            format: function(o) {
              return "extmap:%d" + (o.direction ? "/%s" : "%v") + (o["encrypt-uri"] ? " %s" : "%v") + " %s" + (o.config ? " %s" : "");
            }
          },
          {
            // a=extmap-allow-mixed
            name: "extmapAllowMixed",
            reg: /^(extmap-allow-mixed)/
          },
          {
            // a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:PS1uQCVeeCFCanVmcjkpPywjNWhcYD0mXXtxaVBR|2^20|1:32
            push: "crypto",
            reg: /^crypto:(\d*) ([\w_]*) (\S*)(?: (\S*))?/,
            names: ["id", "suite", "config", "sessionConfig"],
            format: function(o) {
              return o.sessionConfig != null ? "crypto:%d %s %s %s" : "crypto:%d %s %s";
            }
          },
          {
            // a=setup:actpass
            name: "setup",
            reg: /^setup:(\w*)/,
            format: "setup:%s"
          },
          {
            // a=connection:new
            name: "connectionType",
            reg: /^connection:(new|existing)/,
            format: "connection:%s"
          },
          {
            // a=mid:1
            name: "mid",
            reg: /^mid:([^\s]*)/,
            format: "mid:%s"
          },
          {
            // a=msid:0c8b064d-d807-43b4-b434-f92a889d8587 98178685-d409-46e0-8e16-7ef0db0db64a
            name: "msid",
            reg: /^msid:(.*)/,
            format: "msid:%s"
          },
          {
            // a=ptime:20
            name: "ptime",
            reg: /^ptime:(\d*(?:\.\d*)*)/,
            format: "ptime:%d"
          },
          {
            // a=maxptime:60
            name: "maxptime",
            reg: /^maxptime:(\d*(?:\.\d*)*)/,
            format: "maxptime:%d"
          },
          {
            // a=sendrecv
            name: "direction",
            reg: /^(sendrecv|recvonly|sendonly|inactive)/
          },
          {
            // a=ice-lite
            name: "icelite",
            reg: /^(ice-lite)/
          },
          {
            // a=ice-ufrag:F7gI
            name: "iceUfrag",
            reg: /^ice-ufrag:(\S*)/,
            format: "ice-ufrag:%s"
          },
          {
            // a=ice-pwd:x9cml/YzichV2+XlhiMu8g
            name: "icePwd",
            reg: /^ice-pwd:(\S*)/,
            format: "ice-pwd:%s"
          },
          {
            // a=fingerprint:SHA-1 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33
            name: "fingerprint",
            reg: /^fingerprint:(\S*) (\S*)/,
            names: ["type", "hash"],
            format: "fingerprint:%s %s"
          },
          {
            // a=candidate:0 1 UDP 2113667327 203.0.113.1 54400 typ host
            // a=candidate:1162875081 1 udp 2113937151 192.168.34.75 60017 typ host generation 0 network-id 3 network-cost 10
            // a=candidate:3289912957 2 udp 1845501695 193.84.77.194 60017 typ srflx raddr 192.168.34.75 rport 60017 generation 0 network-id 3 network-cost 10
            // a=candidate:229815620 1 tcp 1518280447 192.168.150.19 60017 typ host tcptype active generation 0 network-id 3 network-cost 10
            // a=candidate:3289912957 2 tcp 1845501695 193.84.77.194 60017 typ srflx raddr 192.168.34.75 rport 60017 tcptype passive generation 0 network-id 3 network-cost 10
            push: "candidates",
            reg: /^candidate:(\S*) (\d*) (\S*) (\d*) (\S*) (\d*) typ (\S*)(?: raddr (\S*) rport (\d*))?(?: tcptype (\S*))?(?: generation (\d*))?(?: network-id (\d*))?(?: network-cost (\d*))?/,
            names: ["foundation", "component", "transport", "priority", "ip", "port", "type", "raddr", "rport", "tcptype", "generation", "network-id", "network-cost"],
            format: function(o) {
              var str = "candidate:%s %d %s %d %s %d typ %s";
              str += o.raddr != null ? " raddr %s rport %d" : "%v%v";
              str += o.tcptype != null ? " tcptype %s" : "%v";
              if (o.generation != null) {
                str += " generation %d";
              }
              str += o["network-id"] != null ? " network-id %d" : "%v";
              str += o["network-cost"] != null ? " network-cost %d" : "%v";
              return str;
            }
          },
          {
            // a=end-of-candidates (keep after the candidates line for readability)
            name: "endOfCandidates",
            reg: /^(end-of-candidates)/
          },
          {
            // a=remote-candidates:1 203.0.113.1 54400 2 203.0.113.1 54401 ...
            name: "remoteCandidates",
            reg: /^remote-candidates:(.*)/,
            format: "remote-candidates:%s"
          },
          {
            // a=ice-options:google-ice
            name: "iceOptions",
            reg: /^ice-options:(\S*)/,
            format: "ice-options:%s"
          },
          {
            // a=ssrc:2566107569 cname:t9YU8M1UxTF8Y1A1
            push: "ssrcs",
            reg: /^ssrc:(\d*) ([\w_-]*)(?::(.*))?/,
            names: ["id", "attribute", "value"],
            format: function(o) {
              var str = "ssrc:%d";
              if (o.attribute != null) {
                str += " %s";
                if (o.value != null) {
                  str += ":%s";
                }
              }
              return str;
            }
          },
          {
            // a=ssrc-group:FEC 1 2
            // a=ssrc-group:FEC-FR 3004364195 1080772241
            push: "ssrcGroups",
            // token-char = %x21 / %x23-27 / %x2A-2B / %x2D-2E / %x30-39 / %x41-5A / %x5E-7E
            reg: /^ssrc-group:([\x21\x23\x24\x25\x26\x27\x2A\x2B\x2D\x2E\w]*) (.*)/,
            names: ["semantics", "ssrcs"],
            format: "ssrc-group:%s %s"
          },
          {
            // a=msid-semantic: WMS Jvlam5X3SX1OP6pn20zWogvaKJz5Hjf9OnlV
            name: "msidSemantic",
            reg: /^msid-semantic:\s?(\w*) (\S*)/,
            names: ["semantic", "token"],
            format: "msid-semantic: %s %s"
            // space after ':' is not accidental
          },
          {
            // a=group:BUNDLE audio video
            push: "groups",
            reg: /^group:(\w*) (.*)/,
            names: ["type", "mids"],
            format: "group:%s %s"
          },
          {
            // a=rtcp-mux
            name: "rtcpMux",
            reg: /^(rtcp-mux)/
          },
          {
            // a=rtcp-rsize
            name: "rtcpRsize",
            reg: /^(rtcp-rsize)/
          },
          {
            // a=sctpmap:5000 webrtc-datachannel 1024
            name: "sctpmap",
            reg: /^sctpmap:([\w_/]*) (\S*)(?: (\S*))?/,
            names: ["sctpmapNumber", "app", "maxMessageSize"],
            format: function(o) {
              return o.maxMessageSize != null ? "sctpmap:%s %s %s" : "sctpmap:%s %s";
            }
          },
          {
            // a=x-google-flag:conference
            name: "xGoogleFlag",
            reg: /^x-google-flag:([^\s]*)/,
            format: "x-google-flag:%s"
          },
          {
            // a=rid:1 send max-width=1280;max-height=720;max-fps=30;depend=0
            push: "rids",
            reg: /^rid:([\d\w]+) (\w+)(?: ([\S| ]*))?/,
            names: ["id", "direction", "params"],
            format: function(o) {
              return o.params ? "rid:%s %s %s" : "rid:%s %s";
            }
          },
          {
            // a=imageattr:97 send [x=800,y=640,sar=1.1,q=0.6] [x=480,y=320] recv [x=330,y=250]
            // a=imageattr:* send [x=800,y=640] recv *
            // a=imageattr:100 recv [x=320,y=240]
            push: "imageattrs",
            reg: new RegExp(
              // a=imageattr:97
              "^imageattr:(\\d+|\\*)[\\s\\t]+(send|recv)[\\s\\t]+(\\*|\\[\\S+\\](?:[\\s\\t]+\\[\\S+\\])*)(?:[\\s\\t]+(recv|send)[\\s\\t]+(\\*|\\[\\S+\\](?:[\\s\\t]+\\[\\S+\\])*))?"
            ),
            names: ["pt", "dir1", "attrs1", "dir2", "attrs2"],
            format: function(o) {
              return "imageattr:%s %s %s" + (o.dir2 ? " %s %s" : "");
            }
          },
          {
            // a=simulcast:send 1,2,3;~4,~5 recv 6;~7,~8
            // a=simulcast:recv 1;4,5 send 6;7
            name: "simulcast",
            reg: new RegExp(
              // a=simulcast:
              "^simulcast:(send|recv) ([a-zA-Z0-9\\-_~;,]+)(?:\\s?(send|recv) ([a-zA-Z0-9\\-_~;,]+))?$"
            ),
            names: ["dir1", "list1", "dir2", "list2"],
            format: function(o) {
              return "simulcast:%s %s" + (o.dir2 ? " %s %s" : "");
            }
          },
          {
            // old simulcast draft 03 (implemented by Firefox)
            //   https://tools.ietf.org/html/draft-ietf-mmusic-sdp-simulcast-03
            // a=simulcast: recv pt=97;98 send pt=97
            // a=simulcast: send rid=5;6;7 paused=6,7
            name: "simulcast_03",
            reg: /^simulcast:[\s\t]+([\S+\s\t]+)$/,
            names: ["value"],
            format: "simulcast: %s"
          },
          {
            // a=framerate:25
            // a=framerate:29.97
            name: "framerate",
            reg: /^framerate:(\d+(?:$|\.\d+))/,
            format: "framerate:%s"
          },
          {
            // RFC4570
            // a=source-filter: incl IN IP4 239.5.2.31 10.1.15.5
            name: "sourceFilter",
            reg: /^source-filter: *(excl|incl) (\S*) (IP4|IP6|\*) (\S*) (.*)/,
            names: ["filterMode", "netType", "addressTypes", "destAddress", "srcList"],
            format: "source-filter: %s %s %s %s %s"
          },
          {
            // a=bundle-only
            name: "bundleOnly",
            reg: /^(bundle-only)/
          },
          {
            // a=label:1
            name: "label",
            reg: /^label:(.+)/,
            format: "label:%s"
          },
          {
            // RFC version 26 for SCTP over DTLS
            // https://tools.ietf.org/html/draft-ietf-mmusic-sctp-sdp-26#section-5
            name: "sctpPort",
            reg: /^sctp-port:(\d+)$/,
            format: "sctp-port:%s"
          },
          {
            // RFC version 26 for SCTP over DTLS
            // https://tools.ietf.org/html/draft-ietf-mmusic-sctp-sdp-26#section-6
            name: "maxMessageSize",
            reg: /^max-message-size:(\d+)$/,
            format: "max-message-size:%s"
          },
          {
            // RFC7273
            // a=ts-refclk:ptp=IEEE1588-2008:39-A7-94-FF-FE-07-CB-D0:37
            push: "tsRefClocks",
            reg: /^ts-refclk:([^\s=]*)(?:=(\S*))?/,
            names: ["clksrc", "clksrcExt"],
            format: function(o) {
              return "ts-refclk:%s" + (o.clksrcExt != null ? "=%s" : "");
            }
          },
          {
            // RFC7273
            // a=mediaclk:direct=963214424
            name: "mediaClk",
            reg: /^mediaclk:(?:id=(\S*))? *([^\s=]*)(?:=(\S*))?(?: *rate=(\d+)\/(\d+))?/,
            names: ["id", "mediaClockName", "mediaClockValue", "rateNumerator", "rateDenominator"],
            format: function(o) {
              var str = "mediaclk:";
              str += o.id != null ? "id=%s %s" : "%v%s";
              str += o.mediaClockValue != null ? "=%s" : "";
              str += o.rateNumerator != null ? " rate=%s" : "";
              str += o.rateDenominator != null ? "/%s" : "";
              return str;
            }
          },
          {
            // a=keywds:keywords
            name: "keywords",
            reg: /^keywds:(.+)$/,
            format: "keywds:%s"
          },
          {
            // a=content:main
            name: "content",
            reg: /^content:(.+)/,
            format: "content:%s"
          },
          // BFCP https://tools.ietf.org/html/rfc4583
          {
            // a=floorctrl:c-s
            name: "bfcpFloorCtrl",
            reg: /^floorctrl:(c-only|s-only|c-s)/,
            format: "floorctrl:%s"
          },
          {
            // a=confid:1
            name: "bfcpConfId",
            reg: /^confid:(\d+)/,
            format: "confid:%s"
          },
          {
            // a=userid:1
            name: "bfcpUserId",
            reg: /^userid:(\d+)/,
            format: "userid:%s"
          },
          {
            // a=floorid:1
            name: "bfcpFloorId",
            reg: /^floorid:(.+) (?:m-stream|mstrm):(.+)/,
            names: ["id", "mStream"],
            format: "floorid:%s mstrm:%s"
          },
          {
            // any a= that we don't understand is kept verbatim on media.invalid
            push: "invalid",
            names: ["value"]
          }
        ]
      };
      Object.keys(grammar).forEach(function(key) {
        var objs = grammar[key];
        objs.forEach(function(obj) {
          if (!obj.reg) {
            obj.reg = /(.*)/;
          }
          if (!obj.format) {
            obj.format = "%s";
          }
        });
      });
    }
  });

  // node_modules/sdp-transform/lib/parser.js
  var require_parser = __commonJS({
    "node_modules/sdp-transform/lib/parser.js"(exports) {
      var toIntIfInt = function(v) {
        return String(Number(v)) === v ? Number(v) : v;
      };
      var attachProperties = function(match, location, names, rawName) {
        if (rawName && !names) {
          location[rawName] = toIntIfInt(match[1]);
        } else {
          for (var i = 0; i < names.length; i += 1) {
            if (match[i + 1] != null) {
              location[names[i]] = toIntIfInt(match[i + 1]);
            }
          }
        }
      };
      var parseReg = function(obj, location, content) {
        var needsBlank = obj.name && obj.names;
        if (obj.push && !location[obj.push]) {
          location[obj.push] = [];
        } else if (needsBlank && !location[obj.name]) {
          location[obj.name] = {};
        }
        var keyLocation = obj.push ? {} : (
          // blank object that will be pushed
          needsBlank ? location[obj.name] : location
        );
        attachProperties(content.match(obj.reg), keyLocation, obj.names, obj.name);
        if (obj.push) {
          location[obj.push].push(keyLocation);
        }
      };
      var grammar = require_grammar();
      var validLine = RegExp.prototype.test.bind(/^([a-z])=(.*)/);
      exports.parse = function(sdp) {
        var session = {}, media = [], location = session;
        sdp.split(/(\r\n|\r|\n)/).filter(validLine).forEach(function(l) {
          var type = l[0];
          var content = l.slice(2);
          if (type === "m") {
            media.push({ rtp: [], fmtp: [] });
            location = media[media.length - 1];
          }
          for (var j = 0; j < (grammar[type] || []).length; j += 1) {
            var obj = grammar[type][j];
            if (obj.reg.test(content)) {
              return parseReg(obj, location, content);
            }
          }
        });
        session.media = media;
        return session;
      };
      var paramReducer = function(acc, expr) {
        var s = expr.split(/=(.+)/, 2);
        if (s.length === 2) {
          acc[s[0]] = toIntIfInt(s[1]);
        } else if (s.length === 1 && expr.length > 1) {
          acc[s[0]] = void 0;
        }
        return acc;
      };
      exports.parseParams = function(str) {
        return str.split(/;\s?/).reduce(paramReducer, {});
      };
      exports.parseFmtpConfig = exports.parseParams;
      exports.parsePayloads = function(str) {
        return str.toString().split(" ").map(Number);
      };
      exports.parseRemoteCandidates = function(str) {
        var candidates = [];
        var parts = str.split(" ").map(toIntIfInt);
        for (var i = 0; i < parts.length; i += 3) {
          candidates.push({
            component: parts[i],
            ip: parts[i + 1],
            port: parts[i + 2]
          });
        }
        return candidates;
      };
      exports.parseImageAttributes = function(str) {
        return str.split(" ").map(function(item) {
          return item.substring(1, item.length - 1).split(",").reduce(paramReducer, {});
        });
      };
      exports.parseSimulcastStreamList = function(str) {
        return str.split(";").map(function(stream) {
          return stream.split(",").map(function(format) {
            var scid, paused = false;
            if (format[0] !== "~") {
              scid = toIntIfInt(format);
            } else {
              scid = toIntIfInt(format.substring(1, format.length));
              paused = true;
            }
            return {
              scid,
              paused
            };
          });
        });
      };
    }
  });

  // node_modules/sdp-transform/lib/writer.js
  var require_writer = __commonJS({
    "node_modules/sdp-transform/lib/writer.js"(exports, module) {
      var grammar = require_grammar();
      var formatRegExp = /%[sdv%]/g;
      var format = function(formatStr) {
        var i = 1;
        var args = arguments;
        var len = args.length;
        return formatStr.replace(formatRegExp, function(x) {
          if (i >= len) {
            return x;
          }
          var arg = args[i];
          i += 1;
          switch (x) {
            case "%%":
              return "%";
            case "%s":
              return String(arg);
            case "%d":
              return Number(arg);
            case "%v":
              return "";
          }
        });
      };
      var makeLine = function(type, obj, location) {
        var str = obj.format instanceof Function ? obj.format(obj.push ? location : location[obj.name]) : obj.format;
        var args = [type + "=" + str];
        if (obj.names) {
          for (var i = 0; i < obj.names.length; i += 1) {
            var n = obj.names[i];
            if (obj.name) {
              args.push(location[obj.name][n]);
            } else {
              args.push(location[obj.names[i]]);
            }
          }
        } else {
          args.push(location[obj.name]);
        }
        return format.apply(null, args);
      };
      var defaultOuterOrder = [
        "v",
        "o",
        "s",
        "i",
        "u",
        "e",
        "p",
        "c",
        "b",
        "t",
        "r",
        "z",
        "a"
      ];
      var defaultInnerOrder = ["i", "c", "b", "a"];
      module.exports = function(session, opts) {
        opts = opts || {};
        if (session.version == null) {
          session.version = 0;
        }
        if (session.name == null) {
          session.name = " ";
        }
        session.media.forEach(function(mLine) {
          if (mLine.payloads == null) {
            mLine.payloads = "";
          }
        });
        var outerOrder = opts.outerOrder || defaultOuterOrder;
        var innerOrder = opts.innerOrder || defaultInnerOrder;
        var sdp = [];
        outerOrder.forEach(function(type) {
          grammar[type].forEach(function(obj) {
            if (obj.name in session && session[obj.name] != null) {
              sdp.push(makeLine(type, obj, session));
            } else if (obj.push in session && session[obj.push] != null) {
              session[obj.push].forEach(function(el) {
                sdp.push(makeLine(type, obj, el));
              });
            }
          });
        });
        session.media.forEach(function(mLine) {
          sdp.push(makeLine("m", grammar.m[0], mLine));
          innerOrder.forEach(function(type) {
            grammar[type].forEach(function(obj) {
              if (obj.name in mLine && mLine[obj.name] != null) {
                sdp.push(makeLine(type, obj, mLine));
              } else if (obj.push in mLine && mLine[obj.push] != null) {
                mLine[obj.push].forEach(function(el) {
                  sdp.push(makeLine(type, obj, el));
                });
              }
            });
          });
        });
        return sdp.join("\r\n") + "\r\n";
      };
    }
  });

  // node_modules/sdp-transform/lib/index.js
  var require_lib = __commonJS({
    "node_modules/sdp-transform/lib/index.js"(exports) {
      var parser = require_parser();
      var writer = require_writer();
      var grammar = require_grammar();
      exports.grammar = grammar;
      exports.write = writer;
      exports.parse = parser.parse;
      exports.parseParams = parser.parseParams;
      exports.parseFmtpConfig = parser.parseFmtpConfig;
      exports.parsePayloads = parser.parsePayloads;
      exports.parseRemoteCandidates = parser.parseRemoteCandidates;
      exports.parseImageAttributes = parser.parseImageAttributes;
      exports.parseSimulcastStreamList = parser.parseSimulcastStreamList;
    }
  });

  // node_modules/jssip/lib-es5/SIPMessage.js
  var require_SIPMessage = __commonJS({
    "node_modules/jssip/lib-es5/SIPMessage.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var sdp_transform = require_lib();
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var Utils = require_Utils();
      var NameAddrHeader = require_NameAddrHeader();
      var Grammar = require_Grammar();
      var logger = new Logger("SIPMessage");
      var OutgoingRequest = /* @__PURE__ */ function() {
        function OutgoingRequest2(method, ruri, ua, params, extraHeaders, body) {
          _classCallCheck(this, OutgoingRequest2);
          if (!method || !ruri || !ua) {
            return null;
          }
          params = params || {};
          this.ua = ua;
          this.headers = {};
          this.method = method;
          this.ruri = ruri;
          this.body = body;
          this.extraHeaders = Utils.cloneArray(extraHeaders);
          if (this.ua.configuration.extra_headers) {
            this.extraHeaders = this.extraHeaders.concat(this.ua.configuration.extra_headers);
          }
          if (params.route_set) {
            this.setHeader("route", params.route_set);
          } else if (ua.configuration.use_preloaded_route) {
            this.setHeader("route", "<".concat(ua.transport.sip_uri, ";lr>"));
          }
          this.setHeader("via", "");
          this.setHeader("max-forwards", JsSIP_C.MAX_FORWARDS);
          var to_uri = params.to_uri || ruri;
          var to_params = params.to_tag ? {
            tag: params.to_tag
          } : null;
          var to_display_name = typeof params.to_display_name !== "undefined" ? params.to_display_name : null;
          this.to = new NameAddrHeader(to_uri, to_display_name, to_params);
          this.setHeader("to", this.to.toString());
          var from_uri = params.from_uri || ua.configuration.uri;
          var from_params = {
            tag: params.from_tag || Utils.newTag()
          };
          var display_name;
          if (typeof params.from_display_name !== "undefined") {
            display_name = params.from_display_name;
          } else if (ua.configuration.display_name) {
            display_name = ua.configuration.display_name;
          } else {
            display_name = null;
          }
          this.from = new NameAddrHeader(from_uri, display_name, from_params);
          this.setHeader("from", this.from.toString());
          var call_id = params.call_id || ua.configuration.jssip_id + Utils.createRandomToken(15);
          this.call_id = call_id;
          this.setHeader("call-id", call_id);
          var cseq = params.cseq || Math.floor(Math.random() * 1e4);
          this.cseq = cseq;
          this.setHeader("cseq", "".concat(cseq, " ").concat(method));
        }
        _createClass(OutgoingRequest2, [{
          key: "setHeader",
          value: function setHeader(name, value) {
            var regexp = new RegExp("^\\s*".concat(name, "\\s*:"), "i");
            for (var idx = 0; idx < this.extraHeaders.length; idx++) {
              if (regexp.test(this.extraHeaders[idx])) {
                this.extraHeaders.splice(idx, 1);
              }
            }
            this.headers[Utils.headerize(name)] = Array.isArray(value) ? value : [value];
          }
          /**
           * Get the value of the given header name at the given position.
           * -param {String} name header name
           * -returns {String|undefined} Returns the specified header, null if header doesn't exist.
           */
        }, {
          key: "getHeader",
          value: function getHeader(name) {
            var headers = this.headers[Utils.headerize(name)];
            if (headers) {
              if (headers[0]) {
                return headers[0];
              }
            } else {
              var regexp = new RegExp("^\\s*".concat(name, "\\s*:"), "i");
              var _iterator = _createForOfIteratorHelper(this.extraHeaders), _step;
              try {
                for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                  var header = _step.value;
                  if (regexp.test(header)) {
                    return header.substring(header.indexOf(":") + 1).trim();
                  }
                }
              } catch (err) {
                _iterator.e(err);
              } finally {
                _iterator.f();
              }
            }
            return;
          }
          /**
           * Get the header/s of the given name.
           * -param {String} name header name
           * -returns {Array} Array with all the headers of the specified name.
           */
        }, {
          key: "getHeaders",
          value: function getHeaders(name) {
            var headers = this.headers[Utils.headerize(name)];
            var result = [];
            if (headers) {
              var _iterator2 = _createForOfIteratorHelper(headers), _step2;
              try {
                for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
                  var header = _step2.value;
                  result.push(header);
                }
              } catch (err) {
                _iterator2.e(err);
              } finally {
                _iterator2.f();
              }
              return result;
            } else {
              var regexp = new RegExp("^\\s*".concat(name, "\\s*:"), "i");
              var _iterator3 = _createForOfIteratorHelper(this.extraHeaders), _step3;
              try {
                for (_iterator3.s(); !(_step3 = _iterator3.n()).done; ) {
                  var _header = _step3.value;
                  if (regexp.test(_header)) {
                    result.push(_header.substring(_header.indexOf(":") + 1).trim());
                  }
                }
              } catch (err) {
                _iterator3.e(err);
              } finally {
                _iterator3.f();
              }
              return result;
            }
          }
          /**
           * Verify the existence of the given header.
           * -param {String} name header name
           * -returns {boolean} true if header with given name exists, false otherwise
           */
        }, {
          key: "hasHeader",
          value: function hasHeader(name) {
            if (this.headers[Utils.headerize(name)]) {
              return true;
            } else {
              var regexp = new RegExp("^\\s*".concat(name, "\\s*:"), "i");
              var _iterator4 = _createForOfIteratorHelper(this.extraHeaders), _step4;
              try {
                for (_iterator4.s(); !(_step4 = _iterator4.n()).done; ) {
                  var header = _step4.value;
                  if (regexp.test(header)) {
                    return true;
                  }
                }
              } catch (err) {
                _iterator4.e(err);
              } finally {
                _iterator4.f();
              }
            }
            return false;
          }
          /**
           * Parse the current body as a SDP and store the resulting object
           * into this.sdp.
           * -param {Boolean} force: Parse even if this.sdp already exists.
           *
           * Returns this.sdp.
           */
        }, {
          key: "parseSDP",
          value: function parseSDP(force) {
            if (!force && this.sdp) {
              return this.sdp;
            } else {
              this.sdp = sdp_transform.parse(this.body || "");
              return this.sdp;
            }
          }
        }, {
          key: "toString",
          value: function toString() {
            var msg = "".concat(this.method, " ").concat(this.ruri, " SIP/2.0\r\n");
            for (var headerName in this.headers) {
              if (Object.prototype.hasOwnProperty.call(this.headers, headerName)) {
                var _iterator5 = _createForOfIteratorHelper(this.headers[headerName]), _step5;
                try {
                  for (_iterator5.s(); !(_step5 = _iterator5.n()).done; ) {
                    var headerValue = _step5.value;
                    msg += "".concat(headerName, ": ").concat(headerValue, "\r\n");
                  }
                } catch (err) {
                  _iterator5.e(err);
                } finally {
                  _iterator5.f();
                }
              }
            }
            var _iterator6 = _createForOfIteratorHelper(this.extraHeaders), _step6;
            try {
              for (_iterator6.s(); !(_step6 = _iterator6.n()).done; ) {
                var header = _step6.value;
                msg += "".concat(header.trim(), "\r\n");
              }
            } catch (err) {
              _iterator6.e(err);
            } finally {
              _iterator6.f();
            }
            var supported = [];
            switch (this.method) {
              case JsSIP_C.REGISTER:
                supported.push("path", "gruu");
                break;
              case JsSIP_C.INVITE:
                if (this.ua.configuration.session_timers) {
                  supported.push("timer");
                }
                if (this.ua.contact.pub_gruu || this.ua.contact.temp_gruu) {
                  supported.push("gruu");
                }
                supported.push("ice", "replaces");
                break;
              case JsSIP_C.UPDATE:
                if (this.ua.configuration.session_timers) {
                  supported.push("timer");
                }
                supported.push("ice");
                break;
            }
            supported.push("outbound");
            var userAgent = this.ua.configuration.user_agent || JsSIP_C.USER_AGENT;
            msg += "Allow: ".concat(JsSIP_C.ALLOWED_METHODS, "\r\n");
            msg += "Supported: ".concat(supported, "\r\n");
            msg += "User-Agent: ".concat(userAgent, "\r\n");
            if (this.body) {
              var length = Utils.str_utf8_length(this.body);
              msg += "Content-Length: ".concat(length, "\r\n\r\n");
              msg += this.body;
            } else {
              msg += "Content-Length: 0\r\n\r\n";
            }
            return msg;
          }
        }, {
          key: "clone",
          value: function clone() {
            var request = new OutgoingRequest2(this.method, this.ruri, this.ua);
            Object.keys(this.headers).forEach(function(name) {
              request.headers[name] = this.headers[name].slice();
            }, this);
            request.body = this.body;
            request.extraHeaders = Utils.cloneArray(this.extraHeaders);
            request.to = this.to;
            request.from = this.from;
            request.call_id = this.call_id;
            request.cseq = this.cseq;
            return request;
          }
        }]);
        return OutgoingRequest2;
      }();
      var InitialOutgoingInviteRequest = /* @__PURE__ */ function(_OutgoingRequest) {
        _inherits(InitialOutgoingInviteRequest2, _OutgoingRequest);
        var _super = _createSuper(InitialOutgoingInviteRequest2);
        function InitialOutgoingInviteRequest2(ruri, ua, params, extraHeaders, body) {
          var _this;
          _classCallCheck(this, InitialOutgoingInviteRequest2);
          _this = _super.call(this, JsSIP_C.INVITE, ruri, ua, params, extraHeaders, body);
          _this.transaction = null;
          return _this;
        }
        _createClass(InitialOutgoingInviteRequest2, [{
          key: "cancel",
          value: function cancel(reason) {
            this.transaction.cancel(reason);
          }
        }, {
          key: "clone",
          value: function clone() {
            var request = new InitialOutgoingInviteRequest2(this.ruri, this.ua);
            Object.keys(this.headers).forEach(function(name) {
              request.headers[name] = this.headers[name].slice();
            }, this);
            request.body = this.body;
            request.extraHeaders = Utils.cloneArray(this.extraHeaders);
            request.to = this.to;
            request.from = this.from;
            request.call_id = this.call_id;
            request.cseq = this.cseq;
            request.transaction = this.transaction;
            return request;
          }
        }]);
        return InitialOutgoingInviteRequest2;
      }(OutgoingRequest);
      var IncomingMessage = /* @__PURE__ */ function() {
        function IncomingMessage2() {
          _classCallCheck(this, IncomingMessage2);
          this.data = null;
          this.headers = null;
          this.method = null;
          this.via = null;
          this.via_branch = null;
          this.call_id = null;
          this.cseq = null;
          this.from = null;
          this.from_tag = null;
          this.to = null;
          this.to_tag = null;
          this.body = null;
          this.sdp = null;
        }
        _createClass(IncomingMessage2, [{
          key: "addHeader",
          value: function addHeader(name, value) {
            var header = {
              raw: value
            };
            name = Utils.headerize(name);
            if (this.headers[name]) {
              this.headers[name].push(header);
            } else {
              this.headers[name] = [header];
            }
          }
          /**
           * Get the value of the given header name at the given position.
           */
        }, {
          key: "getHeader",
          value: function getHeader(name) {
            var header = this.headers[Utils.headerize(name)];
            if (header) {
              if (header[0]) {
                return header[0].raw;
              }
            } else {
              return;
            }
          }
          /**
           * Get the header/s of the given name.
           */
        }, {
          key: "getHeaders",
          value: function getHeaders(name) {
            var headers = this.headers[Utils.headerize(name)];
            var result = [];
            if (!headers) {
              return [];
            }
            var _iterator7 = _createForOfIteratorHelper(headers), _step7;
            try {
              for (_iterator7.s(); !(_step7 = _iterator7.n()).done; ) {
                var header = _step7.value;
                result.push(header.raw);
              }
            } catch (err) {
              _iterator7.e(err);
            } finally {
              _iterator7.f();
            }
            return result;
          }
          /**
           * Verify the existence of the given header.
           */
        }, {
          key: "hasHeader",
          value: function hasHeader(name) {
            return this.headers[Utils.headerize(name)] ? true : false;
          }
          /**
          * Parse the given header on the given index.
          * -param {String} name header name
          * -param {Number} [idx=0] header index
          * -returns {Object|undefined} Parsed header object, undefined if the header
          *  is not present or in case of a parsing error.
          */
        }, {
          key: "parseHeader",
          value: function parseHeader(name) {
            var idx = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : 0;
            name = Utils.headerize(name);
            if (!this.headers[name]) {
              logger.debug('header "'.concat(name, '" not present'));
              return;
            } else if (idx >= this.headers[name].length) {
              logger.debug('not so many "'.concat(name, '" headers present'));
              return;
            }
            var header = this.headers[name][idx];
            var value = header.raw;
            if (header.parsed) {
              return header.parsed;
            }
            var parsed = Grammar.parse(value, name.replace(/-/g, "_"));
            if (parsed === -1) {
              this.headers[name].splice(idx, 1);
              logger.debug('error parsing "'.concat(name, '" header field with value "').concat(value, '"'));
              return;
            } else {
              header.parsed = parsed;
              return parsed;
            }
          }
          /**
           * Message Header attribute selector. Alias of parseHeader.
           * -param {String} name header name
           * -param {Number} [idx=0] header index
           * -returns {Object|undefined} Parsed header object, undefined if the header
           *  is not present or in case of a parsing error.
           *
           * -example
           * message.s('via',3).port
           */
        }, {
          key: "s",
          value: function s(name, idx) {
            return this.parseHeader(name, idx);
          }
          /**
          * Replace the value of the given header by the value.
          * -param {String} name header name
          * -param {String} value header value
          */
        }, {
          key: "setHeader",
          value: function setHeader(name, value) {
            var header = {
              raw: value
            };
            this.headers[Utils.headerize(name)] = [header];
          }
          /**
           * Parse the current body as a SDP and store the resulting object
           * into this.sdp.
           * -param {Boolean} force: Parse even if this.sdp already exists.
           *
           * Returns this.sdp.
           */
        }, {
          key: "parseSDP",
          value: function parseSDP(force) {
            if (!force && this.sdp) {
              return this.sdp;
            } else {
              this.sdp = sdp_transform.parse(this.body || "");
              return this.sdp;
            }
          }
        }, {
          key: "toString",
          value: function toString() {
            return this.data;
          }
        }]);
        return IncomingMessage2;
      }();
      var IncomingRequest = /* @__PURE__ */ function(_IncomingMessage) {
        _inherits(IncomingRequest2, _IncomingMessage);
        var _super2 = _createSuper(IncomingRequest2);
        function IncomingRequest2(ua) {
          var _this2;
          _classCallCheck(this, IncomingRequest2);
          _this2 = _super2.call(this);
          _this2.ua = ua;
          _this2.headers = {};
          _this2.ruri = null;
          _this2.transport = null;
          _this2.server_transaction = null;
          return _this2;
        }
        _createClass(IncomingRequest2, [{
          key: "reply",
          value: function reply(code, reason, extraHeaders, body, onSuccess, onFailure) {
            var supported = [];
            var to = this.getHeader("To");
            code = code || null;
            reason = reason || null;
            if (!code || code < 100 || code > 699) {
              throw new TypeError("Invalid status_code: ".concat(code));
            } else if (reason && typeof reason !== "string" && !(reason instanceof String)) {
              throw new TypeError("Invalid reason_phrase: ".concat(reason));
            }
            reason = reason || JsSIP_C.REASON_PHRASE[code] || "";
            extraHeaders = Utils.cloneArray(extraHeaders);
            if (this.ua.configuration.extra_headers) {
              extraHeaders = extraHeaders.concat(this.ua.configuration.extra_headers);
            }
            var response = "SIP/2.0 ".concat(code, " ").concat(reason, "\r\n");
            if (this.method === JsSIP_C.INVITE && code > 100 && code <= 200) {
              var headers = this.getHeaders("record-route");
              var _iterator8 = _createForOfIteratorHelper(headers), _step8;
              try {
                for (_iterator8.s(); !(_step8 = _iterator8.n()).done; ) {
                  var header = _step8.value;
                  response += "Record-Route: ".concat(header, "\r\n");
                }
              } catch (err) {
                _iterator8.e(err);
              } finally {
                _iterator8.f();
              }
            }
            var vias = this.getHeaders("via");
            var _iterator9 = _createForOfIteratorHelper(vias), _step9;
            try {
              for (_iterator9.s(); !(_step9 = _iterator9.n()).done; ) {
                var via = _step9.value;
                response += "Via: ".concat(via, "\r\n");
              }
            } catch (err) {
              _iterator9.e(err);
            } finally {
              _iterator9.f();
            }
            if (!this.to_tag && code > 100) {
              to += ";tag=".concat(Utils.newTag());
            } else if (this.to_tag && !this.s("to").hasParam("tag")) {
              to += ";tag=".concat(this.to_tag);
            }
            response += "To: ".concat(to, "\r\n");
            response += "From: ".concat(this.getHeader("From"), "\r\n");
            response += "Call-ID: ".concat(this.call_id, "\r\n");
            response += "CSeq: ".concat(this.cseq, " ").concat(this.method, "\r\n");
            var _iterator10 = _createForOfIteratorHelper(extraHeaders), _step10;
            try {
              for (_iterator10.s(); !(_step10 = _iterator10.n()).done; ) {
                var _header2 = _step10.value;
                response += "".concat(_header2.trim(), "\r\n");
              }
            } catch (err) {
              _iterator10.e(err);
            } finally {
              _iterator10.f();
            }
            switch (this.method) {
              case JsSIP_C.INVITE:
                if (this.ua.configuration.session_timers) {
                  supported.push("timer");
                }
                if (this.ua.contact.pub_gruu || this.ua.contact.temp_gruu) {
                  supported.push("gruu");
                }
                supported.push("ice", "replaces");
                break;
              case JsSIP_C.UPDATE:
                if (this.ua.configuration.session_timers) {
                  supported.push("timer");
                }
                if (body) {
                  supported.push("ice");
                }
                supported.push("replaces");
            }
            supported.push("outbound");
            if (this.method === JsSIP_C.OPTIONS) {
              response += "Allow: ".concat(JsSIP_C.ALLOWED_METHODS, "\r\n");
              response += "Accept: ".concat(JsSIP_C.ACCEPTED_BODY_TYPES, "\r\n");
            } else if (code === 405) {
              response += "Allow: ".concat(JsSIP_C.ALLOWED_METHODS, "\r\n");
            } else if (code === 415) {
              response += "Accept: ".concat(JsSIP_C.ACCEPTED_BODY_TYPES, "\r\n");
            }
            response += "Supported: ".concat(supported, "\r\n");
            if (body) {
              var length = Utils.str_utf8_length(body);
              response += "Content-Type: application/sdp\r\n";
              response += "Content-Length: ".concat(length, "\r\n\r\n");
              response += body;
            } else {
              response += "Content-Length: ".concat(0, "\r\n\r\n");
            }
            this.server_transaction.receiveResponse(code, response, onSuccess, onFailure);
          }
          /**
          * Stateless reply.
          * -param {Number} code status code
          * -param {String} reason reason phrase
          */
        }, {
          key: "reply_sl",
          value: function reply_sl() {
            var code = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : null;
            var reason = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : null;
            var vias = this.getHeaders("via");
            if (!code || code < 100 || code > 699) {
              throw new TypeError("Invalid status_code: ".concat(code));
            } else if (reason && typeof reason !== "string" && !(reason instanceof String)) {
              throw new TypeError("Invalid reason_phrase: ".concat(reason));
            }
            reason = reason || JsSIP_C.REASON_PHRASE[code] || "";
            var response = "SIP/2.0 ".concat(code, " ").concat(reason, "\r\n");
            var _iterator11 = _createForOfIteratorHelper(vias), _step11;
            try {
              for (_iterator11.s(); !(_step11 = _iterator11.n()).done; ) {
                var via = _step11.value;
                response += "Via: ".concat(via, "\r\n");
              }
            } catch (err) {
              _iterator11.e(err);
            } finally {
              _iterator11.f();
            }
            var to = this.getHeader("To");
            if (!this.to_tag && code > 100) {
              to += ";tag=".concat(Utils.newTag());
            } else if (this.to_tag && !this.s("to").hasParam("tag")) {
              to += ";tag=".concat(this.to_tag);
            }
            response += "To: ".concat(to, "\r\n");
            response += "From: ".concat(this.getHeader("From"), "\r\n");
            response += "Call-ID: ".concat(this.call_id, "\r\n");
            response += "CSeq: ".concat(this.cseq, " ").concat(this.method, "\r\n");
            if (this.ua.configuration.extra_headers) {
              var _iterator12 = _createForOfIteratorHelper(this.ua.configuration.extra_headers), _step12;
              try {
                for (_iterator12.s(); !(_step12 = _iterator12.n()).done; ) {
                  var header = _step12.value;
                  response += "".concat(header.trim(), "\r\n");
                }
              } catch (err) {
                _iterator12.e(err);
              } finally {
                _iterator12.f();
              }
            }
            response += "Content-Length: ".concat(0, "\r\n\r\n");
            this.transport.send(response);
          }
        }]);
        return IncomingRequest2;
      }(IncomingMessage);
      var IncomingResponse = /* @__PURE__ */ function(_IncomingMessage2) {
        _inherits(IncomingResponse2, _IncomingMessage2);
        var _super3 = _createSuper(IncomingResponse2);
        function IncomingResponse2() {
          var _this3;
          _classCallCheck(this, IncomingResponse2);
          _this3 = _super3.call(this);
          _this3.headers = {};
          _this3.status_code = null;
          _this3.reason_phrase = null;
          return _this3;
        }
        return IncomingResponse2;
      }(IncomingMessage);
      module.exports = {
        OutgoingRequest,
        InitialOutgoingInviteRequest,
        IncomingRequest,
        IncomingResponse
      };
    }
  });

  // node_modules/jssip/lib-es5/DigestAuthentication.js
  var require_DigestAuthentication = __commonJS({
    "node_modules/jssip/lib-es5/DigestAuthentication.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var Utils = require_Utils();
      var logger = new Logger("DigestAuthentication");
      module.exports = /* @__PURE__ */ function() {
        function DigestAuthentication(credentials) {
          _classCallCheck(this, DigestAuthentication);
          this._credentials = credentials;
          this._cnonce = null;
          this._nc = 0;
          this._ncHex = "00000000";
          this._algorithm = null;
          this._realm = null;
          this._nonce = null;
          this._opaque = null;
          this._stale = null;
          this._qop = null;
          this._method = null;
          this._uri = null;
          this._ha1 = null;
          this._response = null;
        }
        _createClass(DigestAuthentication, [{
          key: "get",
          value: function get(parameter) {
            switch (parameter) {
              case "realm":
                return this._realm;
              case "ha1":
                return this._ha1;
              default:
                logger.warn('get() | cannot get "%s" parameter', parameter);
                return void 0;
            }
          }
          /**
          * Performs Digest authentication given a SIP request and the challenge
          * received in a response to that request.
          * Returns true if auth was successfully generated, false otherwise.
          */
        }, {
          key: "authenticate",
          value: function authenticate(_ref, challenge) {
            var method = _ref.method, ruri = _ref.ruri, body = _ref.body;
            var cnonce = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : null;
            this._algorithm = challenge.algorithm;
            this._realm = challenge.realm;
            this._nonce = challenge.nonce;
            this._opaque = challenge.opaque;
            this._stale = challenge.stale;
            if (this._algorithm) {
              if (this._algorithm !== "MD5") {
                logger.warn('authenticate() | challenge with Digest algorithm different than "MD5", authentication aborted');
                return false;
              }
            } else {
              this._algorithm = "MD5";
            }
            if (!this._nonce) {
              logger.warn("authenticate() | challenge without Digest nonce, authentication aborted");
              return false;
            }
            if (!this._realm) {
              logger.warn("authenticate() | challenge without Digest realm, authentication aborted");
              return false;
            }
            if (!this._credentials.password) {
              if (!this._credentials.ha1) {
                logger.warn("authenticate() | no plain SIP password nor ha1 provided, authentication aborted");
                return false;
              }
              if (this._credentials.realm !== this._realm) {
                logger.warn('authenticate() | no plain SIP password, and stored `realm` does not match the given `realm`, cannot authenticate [stored:"%s", given:"%s"]', this._credentials.realm, this._realm);
                return false;
              }
            }
            if (challenge.qop) {
              if (challenge.qop.indexOf("auth-int") > -1) {
                this._qop = "auth-int";
              } else if (challenge.qop.indexOf("auth") > -1) {
                this._qop = "auth";
              } else {
                logger.warn('authenticate() | challenge without Digest qop different than "auth" or "auth-int", authentication aborted');
                return false;
              }
            } else {
              this._qop = null;
            }
            this._method = method;
            this._uri = ruri;
            this._cnonce = cnonce || Utils.createRandomToken(12);
            this._nc += 1;
            var hex = Number(this._nc).toString(16);
            this._ncHex = "00000000".substr(0, 8 - hex.length) + hex;
            if (this._nc === 4294967296) {
              this._nc = 1;
              this._ncHex = "00000001";
            }
            if (this._credentials.password) {
              this._ha1 = Utils.calculateMD5("".concat(this._credentials.username, ":").concat(this._realm, ":").concat(this._credentials.password));
            } else {
              this._ha1 = this._credentials.ha1;
            }
            var a2;
            var ha2;
            if (this._qop === "auth") {
              a2 = "".concat(this._method, ":").concat(this._uri);
              ha2 = Utils.calculateMD5(a2);
              logger.debug('authenticate() | using qop=auth [a2:"%s"]', a2);
              this._response = Utils.calculateMD5("".concat(this._ha1, ":").concat(this._nonce, ":").concat(this._ncHex, ":").concat(this._cnonce, ":auth:").concat(ha2));
            } else if (this._qop === "auth-int") {
              a2 = "".concat(this._method, ":").concat(this._uri, ":").concat(Utils.calculateMD5(body ? body : ""));
              ha2 = Utils.calculateMD5(a2);
              logger.debug('authenticate() | using qop=auth-int [a2:"%s"]', a2);
              this._response = Utils.calculateMD5("".concat(this._ha1, ":").concat(this._nonce, ":").concat(this._ncHex, ":").concat(this._cnonce, ":auth-int:").concat(ha2));
            } else if (this._qop === null) {
              a2 = "".concat(this._method, ":").concat(this._uri);
              ha2 = Utils.calculateMD5(a2);
              logger.debug('authenticate() | using qop=null [a2:"%s"]', a2);
              this._response = Utils.calculateMD5("".concat(this._ha1, ":").concat(this._nonce, ":").concat(ha2));
            }
            logger.debug("authenticate() | response generated");
            return true;
          }
          /**
          * Return the Proxy-Authorization or WWW-Authorization header value.
          */
        }, {
          key: "toString",
          value: function toString() {
            var auth_params = [];
            if (!this._response) {
              throw new Error("response field does not exist, cannot generate Authorization header");
            }
            auth_params.push("algorithm=".concat(this._algorithm));
            auth_params.push('username="'.concat(this._credentials.username, '"'));
            auth_params.push('realm="'.concat(this._realm, '"'));
            auth_params.push('nonce="'.concat(this._nonce, '"'));
            auth_params.push('uri="'.concat(this._uri, '"'));
            auth_params.push('response="'.concat(this._response, '"'));
            if (this._opaque) {
              auth_params.push('opaque="'.concat(this._opaque, '"'));
            }
            if (this._qop) {
              auth_params.push("qop=".concat(this._qop));
              auth_params.push('cnonce="'.concat(this._cnonce, '"'));
              auth_params.push("nc=".concat(this._ncHex));
            }
            return "Digest ".concat(auth_params.join(", "));
          }
        }]);
        return DigestAuthentication;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Timers.js
  var require_Timers = __commonJS({
    "node_modules/jssip/lib-es5/Timers.js"(exports, module) {
      "use strict";
      var T1 = 500;
      var T2 = 4e3;
      var T4 = 5e3;
      module.exports = {
        T1,
        T2,
        T4,
        TIMER_B: 64 * T1,
        TIMER_D: 0 * T1,
        TIMER_F: 64 * T1,
        TIMER_H: 64 * T1,
        TIMER_I: 0 * T1,
        TIMER_J: 0 * T1,
        TIMER_K: 0 * T4,
        TIMER_L: 64 * T1,
        TIMER_M: 64 * T1,
        PROVISIONAL_RESPONSE_INTERVAL: 6e4
        // See RFC 3261 Section 13.3.1.1
      };
    }
  });

  // node_modules/jssip/lib-es5/Transactions.js
  var require_Transactions = __commonJS({
    "node_modules/jssip/lib-es5/Transactions.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var SIPMessage = require_SIPMessage();
      var Timers = require_Timers();
      var loggernict = new Logger("NonInviteClientTransaction");
      var loggerict = new Logger("InviteClientTransaction");
      var loggeract = new Logger("AckClientTransaction");
      var loggernist = new Logger("NonInviteServerTransaction");
      var loggerist = new Logger("InviteServerTransaction");
      var C = {
        // Transaction states.
        STATUS_TRYING: 1,
        STATUS_PROCEEDING: 2,
        STATUS_CALLING: 3,
        STATUS_ACCEPTED: 4,
        STATUS_COMPLETED: 5,
        STATUS_TERMINATED: 6,
        STATUS_CONFIRMED: 7,
        // Transaction types.
        NON_INVITE_CLIENT: "nict",
        NON_INVITE_SERVER: "nist",
        INVITE_CLIENT: "ict",
        INVITE_SERVER: "ist"
      };
      var NonInviteClientTransaction = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(NonInviteClientTransaction2, _EventEmitter);
        var _super = _createSuper(NonInviteClientTransaction2);
        function NonInviteClientTransaction2(ua, transport, request, eventHandlers) {
          var _this;
          _classCallCheck(this, NonInviteClientTransaction2);
          _this = _super.call(this);
          _this.type = C.NON_INVITE_CLIENT;
          _this.id = "z9hG4bK".concat(Math.floor(Math.random() * 1e7));
          _this.ua = ua;
          _this.transport = transport;
          _this.request = request;
          _this.eventHandlers = eventHandlers;
          var via = "SIP/2.0/".concat(transport.via_transport);
          via += " ".concat(ua.configuration.via_host, ";branch=").concat(_this.id);
          _this.request.setHeader("via", via);
          _this.ua.newTransaction(_assertThisInitialized(_this));
          return _this;
        }
        _createClass(NonInviteClientTransaction2, [{
          key: "stateChanged",
          value: function stateChanged(state) {
            this.state = state;
            this.emit("stateChanged");
          }
        }, {
          key: "send",
          value: function send() {
            var _this2 = this;
            this.stateChanged(C.STATUS_TRYING);
            this.F = setTimeout(function() {
              _this2.timer_F();
            }, Timers.TIMER_F);
            if (!this.transport.send(this.request)) {
              this.onTransportError();
            }
          }
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            loggernict.debug("transport error occurred, deleting transaction ".concat(this.id));
            clearTimeout(this.F);
            clearTimeout(this.K);
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
            this.eventHandlers.onTransportError();
          }
        }, {
          key: "timer_F",
          value: function timer_F() {
            loggernict.debug("Timer F expired for transaction ".concat(this.id));
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
            this.eventHandlers.onRequestTimeout();
          }
        }, {
          key: "timer_K",
          value: function timer_K() {
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
        }, {
          key: "receiveResponse",
          value: function receiveResponse(response) {
            var _this3 = this;
            var status_code = response.status_code;
            if (status_code < 200) {
              switch (this.state) {
                case C.STATUS_TRYING:
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_PROCEEDING);
                  this.eventHandlers.onReceiveResponse(response);
                  break;
              }
            } else {
              switch (this.state) {
                case C.STATUS_TRYING:
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_COMPLETED);
                  clearTimeout(this.F);
                  if (status_code === 408) {
                    this.eventHandlers.onRequestTimeout();
                  } else {
                    this.eventHandlers.onReceiveResponse(response);
                  }
                  this.K = setTimeout(function() {
                    _this3.timer_K();
                  }, Timers.TIMER_K);
                  break;
                case C.STATUS_COMPLETED:
                  break;
              }
            }
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }]);
        return NonInviteClientTransaction2;
      }(EventEmitter);
      var InviteClientTransaction = /* @__PURE__ */ function(_EventEmitter2) {
        _inherits(InviteClientTransaction2, _EventEmitter2);
        var _super2 = _createSuper(InviteClientTransaction2);
        function InviteClientTransaction2(ua, transport, request, eventHandlers) {
          var _this4;
          _classCallCheck(this, InviteClientTransaction2);
          _this4 = _super2.call(this);
          _this4.type = C.INVITE_CLIENT;
          _this4.id = "z9hG4bK".concat(Math.floor(Math.random() * 1e7));
          _this4.ua = ua;
          _this4.transport = transport;
          _this4.request = request;
          _this4.eventHandlers = eventHandlers;
          request.transaction = _assertThisInitialized(_this4);
          var via = "SIP/2.0/".concat(transport.via_transport);
          via += " ".concat(ua.configuration.via_host, ";branch=").concat(_this4.id);
          _this4.request.setHeader("via", via);
          _this4.ua.newTransaction(_assertThisInitialized(_this4));
          return _this4;
        }
        _createClass(InviteClientTransaction2, [{
          key: "stateChanged",
          value: function stateChanged(state) {
            this.state = state;
            this.emit("stateChanged");
          }
        }, {
          key: "send",
          value: function send() {
            var _this5 = this;
            this.stateChanged(C.STATUS_CALLING);
            this.B = setTimeout(function() {
              _this5.timer_B();
            }, Timers.TIMER_B);
            if (!this.transport.send(this.request)) {
              this.onTransportError();
            }
          }
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            clearTimeout(this.B);
            clearTimeout(this.D);
            clearTimeout(this.M);
            if (this.state !== C.STATUS_ACCEPTED) {
              loggerict.debug("transport error occurred, deleting transaction ".concat(this.id));
              this.eventHandlers.onTransportError();
            }
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
          // RFC 6026 7.2.
        }, {
          key: "timer_M",
          value: function timer_M() {
            loggerict.debug("Timer M expired for transaction ".concat(this.id));
            if (this.state === C.STATUS_ACCEPTED) {
              clearTimeout(this.B);
              this.stateChanged(C.STATUS_TERMINATED);
              this.ua.destroyTransaction(this);
            }
          }
          // RFC 3261 17.1.1.
        }, {
          key: "timer_B",
          value: function timer_B() {
            loggerict.debug("Timer B expired for transaction ".concat(this.id));
            if (this.state === C.STATUS_CALLING) {
              this.stateChanged(C.STATUS_TERMINATED);
              this.ua.destroyTransaction(this);
              this.eventHandlers.onRequestTimeout();
            }
          }
        }, {
          key: "timer_D",
          value: function timer_D() {
            loggerict.debug("Timer D expired for transaction ".concat(this.id));
            clearTimeout(this.B);
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
        }, {
          key: "sendACK",
          value: function sendACK(response) {
            var _this6 = this;
            var ack = new SIPMessage.OutgoingRequest(JsSIP_C.ACK, this.request.ruri, this.ua, {
              "route_set": this.request.getHeaders("route"),
              "call_id": this.request.getHeader("call-id"),
              "cseq": this.request.cseq
            });
            ack.setHeader("from", this.request.getHeader("from"));
            ack.setHeader("via", this.request.getHeader("via"));
            ack.setHeader("to", response.getHeader("to"));
            this.D = setTimeout(function() {
              _this6.timer_D();
            }, Timers.TIMER_D);
            this.transport.send(ack);
          }
        }, {
          key: "cancel",
          value: function cancel(reason) {
            if (this.state !== C.STATUS_PROCEEDING) {
              return;
            }
            var cancel2 = new SIPMessage.OutgoingRequest(JsSIP_C.CANCEL, this.request.ruri, this.ua, {
              "route_set": this.request.getHeaders("route"),
              "call_id": this.request.getHeader("call-id"),
              "cseq": this.request.cseq
            });
            cancel2.setHeader("from", this.request.getHeader("from"));
            cancel2.setHeader("via", this.request.getHeader("via"));
            cancel2.setHeader("to", this.request.getHeader("to"));
            if (reason) {
              cancel2.setHeader("reason", reason);
            }
            this.transport.send(cancel2);
          }
        }, {
          key: "receiveResponse",
          value: function receiveResponse(response) {
            var _this7 = this;
            var status_code = response.status_code;
            if (status_code >= 100 && status_code <= 199) {
              switch (this.state) {
                case C.STATUS_CALLING:
                  this.stateChanged(C.STATUS_PROCEEDING);
                  this.eventHandlers.onReceiveResponse(response);
                  break;
                case C.STATUS_PROCEEDING:
                  this.eventHandlers.onReceiveResponse(response);
                  break;
              }
            } else if (status_code >= 200 && status_code <= 299) {
              switch (this.state) {
                case C.STATUS_CALLING:
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_ACCEPTED);
                  this.M = setTimeout(function() {
                    _this7.timer_M();
                  }, Timers.TIMER_M);
                  this.eventHandlers.onReceiveResponse(response);
                  break;
                case C.STATUS_ACCEPTED:
                  this.eventHandlers.onReceiveResponse(response);
                  break;
              }
            } else if (status_code >= 300 && status_code <= 699) {
              switch (this.state) {
                case C.STATUS_CALLING:
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_COMPLETED);
                  this.sendACK(response);
                  this.eventHandlers.onReceiveResponse(response);
                  break;
                case C.STATUS_COMPLETED:
                  this.sendACK(response);
                  break;
              }
            }
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }]);
        return InviteClientTransaction2;
      }(EventEmitter);
      var AckClientTransaction = /* @__PURE__ */ function(_EventEmitter3) {
        _inherits(AckClientTransaction2, _EventEmitter3);
        var _super3 = _createSuper(AckClientTransaction2);
        function AckClientTransaction2(ua, transport, request, eventHandlers) {
          var _this8;
          _classCallCheck(this, AckClientTransaction2);
          _this8 = _super3.call(this);
          _this8.id = "z9hG4bK".concat(Math.floor(Math.random() * 1e7));
          _this8.transport = transport;
          _this8.request = request;
          _this8.eventHandlers = eventHandlers;
          var via = "SIP/2.0/".concat(transport.via_transport);
          via += " ".concat(ua.configuration.via_host, ";branch=").concat(_this8.id);
          _this8.request.setHeader("via", via);
          return _this8;
        }
        _createClass(AckClientTransaction2, [{
          key: "send",
          value: function send() {
            if (!this.transport.send(this.request)) {
              this.onTransportError();
            }
          }
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            loggeract.debug("transport error occurred for transaction ".concat(this.id));
            this.eventHandlers.onTransportError();
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }]);
        return AckClientTransaction2;
      }(EventEmitter);
      var NonInviteServerTransaction = /* @__PURE__ */ function(_EventEmitter4) {
        _inherits(NonInviteServerTransaction2, _EventEmitter4);
        var _super4 = _createSuper(NonInviteServerTransaction2);
        function NonInviteServerTransaction2(ua, transport, request) {
          var _this9;
          _classCallCheck(this, NonInviteServerTransaction2);
          _this9 = _super4.call(this);
          _this9.type = C.NON_INVITE_SERVER;
          _this9.id = request.via_branch;
          _this9.ua = ua;
          _this9.transport = transport;
          _this9.request = request;
          _this9.last_response = "";
          request.server_transaction = _assertThisInitialized(_this9);
          _this9.state = C.STATUS_TRYING;
          ua.newTransaction(_assertThisInitialized(_this9));
          return _this9;
        }
        _createClass(NonInviteServerTransaction2, [{
          key: "stateChanged",
          value: function stateChanged(state) {
            this.state = state;
            this.emit("stateChanged");
          }
        }, {
          key: "timer_J",
          value: function timer_J() {
            loggernist.debug("Timer J expired for transaction ".concat(this.id));
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            if (!this.transportError) {
              this.transportError = true;
              loggernist.debug("transport error occurred, deleting transaction ".concat(this.id));
              clearTimeout(this.J);
              this.stateChanged(C.STATUS_TERMINATED);
              this.ua.destroyTransaction(this);
            }
          }
        }, {
          key: "receiveResponse",
          value: function receiveResponse(status_code, response, onSuccess, onFailure) {
            var _this10 = this;
            if (status_code === 100) {
              switch (this.state) {
                case C.STATUS_TRYING:
                  this.stateChanged(C.STATUS_PROCEEDING);
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                  }
                  break;
                case C.STATUS_PROCEEDING:
                  this.last_response = response;
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                    if (onFailure) {
                      onFailure();
                    }
                  } else if (onSuccess) {
                    onSuccess();
                  }
                  break;
              }
            } else if (status_code >= 200 && status_code <= 699) {
              switch (this.state) {
                case C.STATUS_TRYING:
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_COMPLETED);
                  this.last_response = response;
                  this.J = setTimeout(function() {
                    _this10.timer_J();
                  }, Timers.TIMER_J);
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                    if (onFailure) {
                      onFailure();
                    }
                  } else if (onSuccess) {
                    onSuccess();
                  }
                  break;
                case C.STATUS_COMPLETED:
                  break;
              }
            }
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }]);
        return NonInviteServerTransaction2;
      }(EventEmitter);
      var InviteServerTransaction = /* @__PURE__ */ function(_EventEmitter5) {
        _inherits(InviteServerTransaction2, _EventEmitter5);
        var _super5 = _createSuper(InviteServerTransaction2);
        function InviteServerTransaction2(ua, transport, request) {
          var _this11;
          _classCallCheck(this, InviteServerTransaction2);
          _this11 = _super5.call(this);
          _this11.type = C.INVITE_SERVER;
          _this11.id = request.via_branch;
          _this11.ua = ua;
          _this11.transport = transport;
          _this11.request = request;
          _this11.last_response = "";
          request.server_transaction = _assertThisInitialized(_this11);
          _this11.state = C.STATUS_PROCEEDING;
          ua.newTransaction(_assertThisInitialized(_this11));
          _this11.resendProvisionalTimer = null;
          request.reply(100);
          return _this11;
        }
        _createClass(InviteServerTransaction2, [{
          key: "stateChanged",
          value: function stateChanged(state) {
            this.state = state;
            this.emit("stateChanged");
          }
        }, {
          key: "timer_H",
          value: function timer_H() {
            loggerist.debug("Timer H expired for transaction ".concat(this.id));
            if (this.state === C.STATUS_COMPLETED) {
              loggerist.debug("ACK not received, dialog will be terminated");
            }
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
        }, {
          key: "timer_I",
          value: function timer_I() {
            this.stateChanged(C.STATUS_TERMINATED);
            this.ua.destroyTransaction(this);
          }
          // RFC 6026 7.1.
        }, {
          key: "timer_L",
          value: function timer_L() {
            loggerist.debug("Timer L expired for transaction ".concat(this.id));
            if (this.state === C.STATUS_ACCEPTED) {
              this.stateChanged(C.STATUS_TERMINATED);
              this.ua.destroyTransaction(this);
            }
          }
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            if (!this.transportError) {
              this.transportError = true;
              loggerist.debug("transport error occurred, deleting transaction ".concat(this.id));
              if (this.resendProvisionalTimer !== null) {
                clearInterval(this.resendProvisionalTimer);
                this.resendProvisionalTimer = null;
              }
              clearTimeout(this.L);
              clearTimeout(this.H);
              clearTimeout(this.I);
              this.stateChanged(C.STATUS_TERMINATED);
              this.ua.destroyTransaction(this);
            }
          }
        }, {
          key: "resend_provisional",
          value: function resend_provisional() {
            if (!this.transport.send(this.last_response)) {
              this.onTransportError();
            }
          }
          // INVITE Server Transaction RFC 3261 17.2.1.
        }, {
          key: "receiveResponse",
          value: function receiveResponse(status_code, response, onSuccess, onFailure) {
            var _this12 = this;
            if (status_code >= 100 && status_code <= 199) {
              switch (this.state) {
                case C.STATUS_PROCEEDING:
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                  }
                  this.last_response = response;
                  break;
              }
            }
            if (status_code > 100 && status_code <= 199 && this.state === C.STATUS_PROCEEDING) {
              if (this.resendProvisionalTimer === null) {
                this.resendProvisionalTimer = setInterval(function() {
                  _this12.resend_provisional();
                }, Timers.PROVISIONAL_RESPONSE_INTERVAL);
              }
            } else if (status_code >= 200 && status_code <= 299) {
              switch (this.state) {
                case C.STATUS_PROCEEDING:
                  this.stateChanged(C.STATUS_ACCEPTED);
                  this.last_response = response;
                  this.L = setTimeout(function() {
                    _this12.timer_L();
                  }, Timers.TIMER_L);
                  if (this.resendProvisionalTimer !== null) {
                    clearInterval(this.resendProvisionalTimer);
                    this.resendProvisionalTimer = null;
                  }
                /* falls through */
                case C.STATUS_ACCEPTED:
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                    if (onFailure) {
                      onFailure();
                    }
                  } else if (onSuccess) {
                    onSuccess();
                  }
                  break;
              }
            } else if (status_code >= 300 && status_code <= 699) {
              switch (this.state) {
                case C.STATUS_PROCEEDING:
                  if (this.resendProvisionalTimer !== null) {
                    clearInterval(this.resendProvisionalTimer);
                    this.resendProvisionalTimer = null;
                  }
                  if (!this.transport.send(response)) {
                    this.onTransportError();
                    if (onFailure) {
                      onFailure();
                    }
                  } else {
                    this.stateChanged(C.STATUS_COMPLETED);
                    this.H = setTimeout(function() {
                      _this12.timer_H();
                    }, Timers.TIMER_H);
                    if (onSuccess) {
                      onSuccess();
                    }
                  }
                  break;
              }
            }
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }]);
        return InviteServerTransaction2;
      }(EventEmitter);
      function checkTransaction(_ref, request) {
        var _transactions = _ref._transactions;
        var tr;
        switch (request.method) {
          case JsSIP_C.INVITE:
            tr = _transactions.ist[request.via_branch];
            if (tr) {
              switch (tr.state) {
                case C.STATUS_PROCEEDING:
                  tr.transport.send(tr.last_response);
                  break;
                // RFC 6026 7.1 Invite retransmission.
                // Received while in C.STATUS_ACCEPTED state. Absorb it.
                case C.STATUS_ACCEPTED:
                  break;
              }
              return true;
            }
            break;
          case JsSIP_C.ACK:
            tr = _transactions.ist[request.via_branch];
            if (tr) {
              if (tr.state === C.STATUS_ACCEPTED) {
                return false;
              } else if (tr.state === C.STATUS_COMPLETED) {
                tr.state = C.STATUS_CONFIRMED;
                tr.I = setTimeout(function() {
                  tr.timer_I();
                }, Timers.TIMER_I);
                return true;
              }
            } else {
              return false;
            }
            break;
          case JsSIP_C.CANCEL:
            tr = _transactions.ist[request.via_branch];
            if (tr) {
              request.reply_sl(200);
              if (tr.state === C.STATUS_PROCEEDING) {
                return false;
              } else {
                return true;
              }
            } else {
              request.reply_sl(481);
              return true;
            }
          default:
            tr = _transactions.nist[request.via_branch];
            if (tr) {
              switch (tr.state) {
                case C.STATUS_TRYING:
                  break;
                case C.STATUS_PROCEEDING:
                case C.STATUS_COMPLETED:
                  tr.transport.send(tr.last_response);
                  break;
              }
              return true;
            }
            break;
        }
      }
      module.exports = {
        C,
        NonInviteClientTransaction,
        InviteClientTransaction,
        AckClientTransaction,
        NonInviteServerTransaction,
        InviteServerTransaction,
        checkTransaction
      };
    }
  });

  // node_modules/jssip/lib-es5/RequestSender.js
  var require_RequestSender = __commonJS({
    "node_modules/jssip/lib-es5/RequestSender.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var DigestAuthentication = require_DigestAuthentication();
      var Transactions = require_Transactions();
      var logger = new Logger("RequestSender");
      var EventHandlers = {
        onRequestTimeout: function onRequestTimeout() {
        },
        onTransportError: function onTransportError() {
        },
        onReceiveResponse: function onReceiveResponse() {
        },
        onAuthenticated: function onAuthenticated() {
        }
      };
      module.exports = /* @__PURE__ */ function() {
        function RequestSender(ua, request, eventHandlers) {
          _classCallCheck(this, RequestSender);
          this._ua = ua;
          this._eventHandlers = eventHandlers;
          this._method = request.method;
          this._request = request;
          this._auth = null;
          this._challenged = false;
          this._staled = false;
          for (var handler in EventHandlers) {
            if (Object.prototype.hasOwnProperty.call(EventHandlers, handler)) {
              if (!this._eventHandlers[handler]) {
                this._eventHandlers[handler] = EventHandlers[handler];
              }
            }
          }
          if (ua.status === ua.C.STATUS_USER_CLOSED && (this._method !== JsSIP_C.BYE || this._method !== JsSIP_C.ACK)) {
            this._eventHandlers.onTransportError();
          }
        }
        _createClass(RequestSender, [{
          key: "send",
          value: function send() {
            var _this = this;
            var eventHandlers = {
              onRequestTimeout: function onRequestTimeout() {
                _this._eventHandlers.onRequestTimeout();
              },
              onTransportError: function onTransportError() {
                _this._eventHandlers.onTransportError();
              },
              onReceiveResponse: function onReceiveResponse(response) {
                _this._receiveResponse(response);
              }
            };
            switch (this._method) {
              case "INVITE":
                this.clientTransaction = new Transactions.InviteClientTransaction(this._ua, this._ua.transport, this._request, eventHandlers);
                break;
              case "ACK":
                this.clientTransaction = new Transactions.AckClientTransaction(this._ua, this._ua.transport, this._request, eventHandlers);
                break;
              default:
                this.clientTransaction = new Transactions.NonInviteClientTransaction(this._ua, this._ua.transport, this._request, eventHandlers);
            }
            if (this._ua._configuration.authorization_jwt) {
              this._request.setHeader("Authorization", this._ua._configuration.authorization_jwt);
            }
            this.clientTransaction.send();
          }
          /**
          * Called from client transaction when receiving a correct response to the request.
          * Authenticate request if needed or pass the response back to the applicant.
          */
        }, {
          key: "_receiveResponse",
          value: function _receiveResponse(response) {
            var challenge;
            var authorization_header_name;
            var status_code = response.status_code;
            if ((status_code === 401 || status_code === 407) && (this._ua.configuration.password !== null || this._ua.configuration.ha1 !== null)) {
              if (response.status_code === 401) {
                challenge = response.parseHeader("www-authenticate");
                authorization_header_name = "authorization";
              } else {
                challenge = response.parseHeader("proxy-authenticate");
                authorization_header_name = "proxy-authorization";
              }
              if (!challenge) {
                logger.debug("".concat(response.status_code, " with wrong or missing challenge, cannot authenticate"));
                this._eventHandlers.onReceiveResponse(response);
                return;
              }
              if (!this._challenged || !this._staled && challenge.stale === true) {
                if (!this._auth) {
                  this._auth = new DigestAuthentication({
                    username: this._ua.configuration.authorization_user,
                    password: this._ua.configuration.password,
                    realm: this._ua.configuration.realm,
                    ha1: this._ua.configuration.ha1
                  });
                }
                if (!this._auth.authenticate(this._request, challenge)) {
                  this._eventHandlers.onReceiveResponse(response);
                  return;
                }
                this._challenged = true;
                this._ua.set("realm", this._auth.get("realm"));
                this._ua.set("ha1", this._auth.get("ha1"));
                if (challenge.stale) {
                  this._staled = true;
                }
                this._request = this._request.clone();
                this._request.cseq += 1;
                this._request.setHeader("cseq", "".concat(this._request.cseq, " ").concat(this._method));
                this._request.setHeader(authorization_header_name, this._auth.toString());
                this._eventHandlers.onAuthenticated(this._request);
                this.send();
              } else {
                this._eventHandlers.onReceiveResponse(response);
              }
            } else {
              this._eventHandlers.onReceiveResponse(response);
            }
          }
        }]);
        return RequestSender;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Registrator.js
  var require_Registrator = __commonJS({
    "node_modules/jssip/lib-es5/Registrator.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var Utils = require_Utils();
      var JsSIP_C = require_Constants();
      var SIPMessage = require_SIPMessage();
      var RequestSender = require_RequestSender();
      var logger = new Logger("Registrator");
      var MIN_REGISTER_EXPIRES = 10;
      module.exports = /* @__PURE__ */ function() {
        function Registrator(ua, transport) {
          _classCallCheck(this, Registrator);
          this._reg_id = 1;
          this._ua = ua;
          this._transport = transport;
          this._registrar = ua.configuration.registrar_server;
          this._expires = ua.configuration.register_expires;
          this._call_id = Utils.createRandomToken(22);
          this._cseq = 0;
          this._to_uri = ua.configuration.uri;
          this._registrationTimer = null;
          this._registering = false;
          this._registered = false;
          this._contact = this._ua.contact.toString();
          this._contact += ";+sip.ice";
          this._extraHeaders = [];
          this._extraContactParams = "";
          this._sipInstance = '"<urn:uuid:'.concat(this._ua.configuration.instance_id, '>"');
          this._contact += ";reg-id=".concat(this._reg_id);
          this._contact += ";+sip.instance=".concat(this._sipInstance);
        }
        _createClass(Registrator, [{
          key: "setExtraHeaders",
          value: function setExtraHeaders(extraHeaders) {
            if (!Array.isArray(extraHeaders)) {
              extraHeaders = [];
            }
            this._extraHeaders = extraHeaders.slice();
          }
        }, {
          key: "setExtraContactParams",
          value: function setExtraContactParams(extraContactParams) {
            if (!(extraContactParams instanceof Object)) {
              extraContactParams = {};
            }
            this._extraContactParams = "";
            for (var param_key in extraContactParams) {
              if (Object.prototype.hasOwnProperty.call(extraContactParams, param_key)) {
                var param_value = extraContactParams[param_key];
                this._extraContactParams += ";".concat(param_key);
                if (param_value) {
                  this._extraContactParams += "=".concat(param_value);
                }
              }
            }
          }
        }, {
          key: "register",
          value: function register() {
            var _this = this;
            if (this._registering) {
              logger.debug("Register request in progress...");
              return;
            }
            var extraHeaders = this._extraHeaders.slice();
            extraHeaders.push("Contact: ".concat(this._contact, ";expires=").concat(this._expires).concat(this._extraContactParams));
            extraHeaders.push("Expires: ".concat(this._expires));
            var request = new SIPMessage.OutgoingRequest(JsSIP_C.REGISTER, this._registrar, this._ua, {
              "to_uri": this._to_uri,
              "call_id": this._call_id,
              "cseq": this._cseq += 1
            }, extraHeaders);
            var request_sender = new RequestSender(this._ua, request, {
              onRequestTimeout: function onRequestTimeout() {
                _this._registrationFailure(null, JsSIP_C.causes.REQUEST_TIMEOUT);
              },
              onTransportError: function onTransportError() {
                _this._registrationFailure(null, JsSIP_C.causes.CONNECTION_ERROR);
              },
              // Increase the CSeq on authentication.
              onAuthenticated: function onAuthenticated() {
                _this._cseq += 1;
              },
              onReceiveResponse: function onReceiveResponse(response) {
                if (response.cseq !== _this._cseq) {
                  return;
                }
                if (_this._registrationTimer !== null) {
                  clearTimeout(_this._registrationTimer);
                  _this._registrationTimer = null;
                }
                switch (true) {
                  case /^1[0-9]{2}$/.test(response.status_code): {
                    break;
                  }
                  case /^2[0-9]{2}$/.test(response.status_code): {
                    _this._registering = false;
                    if (!response.hasHeader("Contact")) {
                      logger.debug("no Contact header in response to REGISTER, response ignored");
                      break;
                    }
                    var contacts = response.headers["Contact"].reduce(function(a, b) {
                      return a.concat(b.parsed);
                    }, []);
                    var contact = contacts.find(function(element) {
                      return _this._sipInstance === element.getParam("+sip.instance") && _this._reg_id === parseInt(element.getParam("reg-id"));
                    });
                    if (!contact) {
                      contact = contacts.find(function(element) {
                        return element.uri.user === _this._ua.contact.uri.user;
                      });
                    }
                    if (!contact) {
                      logger.debug("no Contact header pointing to us, response ignored");
                      break;
                    }
                    var expires = contact.getParam("expires");
                    if (!expires && response.hasHeader("expires")) {
                      expires = response.getHeader("expires");
                    }
                    if (!expires) {
                      expires = _this._expires;
                    }
                    expires = Number(expires);
                    if (expires < MIN_REGISTER_EXPIRES) expires = MIN_REGISTER_EXPIRES;
                    var timeout = expires > 64 ? expires * 1e3 / 2 + Math.floor((expires / 2 - 32) * 1e3 * Math.random()) : expires * 1e3 - 5e3;
                    _this._registrationTimer = setTimeout(function() {
                      _this._registrationTimer = null;
                      if (_this._ua.listeners("registrationExpiring").length === 0) {
                        _this.register();
                      } else {
                        _this._ua.emit("registrationExpiring");
                      }
                    }, timeout);
                    if (contact.hasParam("temp-gruu")) {
                      _this._ua.contact.temp_gruu = contact.getParam("temp-gruu").replace(/"/g, "");
                    }
                    if (contact.hasParam("pub-gruu")) {
                      _this._ua.contact.pub_gruu = contact.getParam("pub-gruu").replace(/"/g, "");
                    }
                    if (!_this._registered) {
                      _this._registered = true;
                      _this._ua.registered({
                        response
                      });
                    }
                    break;
                  }
                  // Interval too brief RFC3261 10.2.8.
                  case /^423$/.test(response.status_code): {
                    if (response.hasHeader("min-expires")) {
                      _this._expires = Number(response.getHeader("min-expires"));
                      if (_this._expires < MIN_REGISTER_EXPIRES) _this._expires = MIN_REGISTER_EXPIRES;
                      _this.register();
                    } else {
                      logger.debug("423 response received for REGISTER without Min-Expires");
                      _this._registrationFailure(response, JsSIP_C.causes.SIP_FAILURE_CODE);
                    }
                    break;
                  }
                  default: {
                    var cause = Utils.sipErrorCause(response.status_code);
                    _this._registrationFailure(response, cause);
                  }
                }
              }
            });
            this._registering = true;
            request_sender.send();
          }
        }, {
          key: "unregister",
          value: function unregister() {
            var _this2 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            if (!this._registered) {
              logger.debug("already unregistered");
              return;
            }
            this._registered = false;
            if (this._registrationTimer !== null) {
              clearTimeout(this._registrationTimer);
              this._registrationTimer = null;
            }
            var extraHeaders = this._extraHeaders.slice();
            if (options.all) {
              extraHeaders.push("Contact: *".concat(this._extraContactParams));
            } else {
              extraHeaders.push("Contact: ".concat(this._contact, ";expires=0").concat(this._extraContactParams));
            }
            extraHeaders.push("Expires: 0");
            var request = new SIPMessage.OutgoingRequest(JsSIP_C.REGISTER, this._registrar, this._ua, {
              "to_uri": this._to_uri,
              "call_id": this._call_id,
              "cseq": this._cseq += 1
            }, extraHeaders);
            var request_sender = new RequestSender(this._ua, request, {
              onRequestTimeout: function onRequestTimeout() {
                _this2._unregistered(null, JsSIP_C.causes.REQUEST_TIMEOUT);
              },
              onTransportError: function onTransportError() {
                _this2._unregistered(null, JsSIP_C.causes.CONNECTION_ERROR);
              },
              // Increase the CSeq on authentication.
              onAuthenticated: function onAuthenticated() {
                _this2._cseq += 1;
              },
              onReceiveResponse: function onReceiveResponse(response) {
                switch (true) {
                  case /^1[0-9]{2}$/.test(response.status_code):
                    break;
                  case /^2[0-9]{2}$/.test(response.status_code):
                    _this2._unregistered(response);
                    break;
                  default: {
                    var cause = Utils.sipErrorCause(response.status_code);
                    _this2._unregistered(response, cause);
                  }
                }
              }
            });
            request_sender.send();
          }
        }, {
          key: "close",
          value: function close() {
            if (this._registered) {
              this.unregister();
            }
          }
        }, {
          key: "onTransportClosed",
          value: function onTransportClosed() {
            this._registering = false;
            if (this._registrationTimer !== null) {
              clearTimeout(this._registrationTimer);
              this._registrationTimer = null;
            }
            if (this._registered) {
              this._registered = false;
              this._ua.unregistered({});
            }
          }
        }, {
          key: "_registrationFailure",
          value: function _registrationFailure(response, cause) {
            this._registering = false;
            this._ua.registrationFailed({
              response: response || null,
              cause
            });
            if (this._registered) {
              this._registered = false;
              this._ua.unregistered({
                response: response || null,
                cause
              });
            }
          }
        }, {
          key: "_unregistered",
          value: function _unregistered(response, cause) {
            this._registering = false;
            this._registered = false;
            this._ua.unregistered({
              response: response || null,
              cause: cause || null
            });
          }
        }, {
          key: "registered",
          get: function get() {
            return this._registered;
          }
        }]);
        return Registrator;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Dialog/RequestSender.js
  var require_RequestSender2 = __commonJS({
    "node_modules/jssip/lib-es5/Dialog/RequestSender.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var JsSIP_C = require_Constants();
      var Transactions = require_Transactions();
      var RequestSender = require_RequestSender();
      var EventHandlers = {
        onRequestTimeout: function onRequestTimeout() {
        },
        onTransportError: function onTransportError() {
        },
        onSuccessResponse: function onSuccessResponse() {
        },
        onErrorResponse: function onErrorResponse() {
        },
        onAuthenticated: function onAuthenticated() {
        },
        onDialogError: function onDialogError() {
        }
      };
      module.exports = /* @__PURE__ */ function() {
        function DialogRequestSender(dialog, request, eventHandlers) {
          _classCallCheck(this, DialogRequestSender);
          this._dialog = dialog;
          this._ua = dialog._ua;
          this._request = request;
          this._eventHandlers = eventHandlers;
          this._reattempt = false;
          this._reattemptTimer = null;
          for (var handler in EventHandlers) {
            if (Object.prototype.hasOwnProperty.call(EventHandlers, handler)) {
              if (!this._eventHandlers[handler]) {
                this._eventHandlers[handler] = EventHandlers[handler];
              }
            }
          }
        }
        _createClass(DialogRequestSender, [{
          key: "send",
          value: function send() {
            var _this = this;
            var request_sender = new RequestSender(this._ua, this._request, {
              onRequestTimeout: function onRequestTimeout() {
                _this._eventHandlers.onRequestTimeout();
              },
              onTransportError: function onTransportError() {
                _this._eventHandlers.onTransportError();
              },
              onAuthenticated: function onAuthenticated(request) {
                _this._eventHandlers.onAuthenticated(request);
              },
              onReceiveResponse: function onReceiveResponse(response) {
                _this._receiveResponse(response);
              }
            });
            request_sender.send();
            if ((this._request.method === JsSIP_C.INVITE || this._request.method === JsSIP_C.UPDATE && this._request.body) && request_sender.clientTransaction.state !== Transactions.C.STATUS_TERMINATED) {
              this._dialog.uac_pending_reply = true;
              var stateChanged = function stateChanged2() {
                if (request_sender.clientTransaction.state === Transactions.C.STATUS_ACCEPTED || request_sender.clientTransaction.state === Transactions.C.STATUS_COMPLETED || request_sender.clientTransaction.state === Transactions.C.STATUS_TERMINATED) {
                  request_sender.clientTransaction.removeListener("stateChanged", stateChanged2);
                  _this._dialog.uac_pending_reply = false;
                }
              };
              request_sender.clientTransaction.on("stateChanged", stateChanged);
            }
          }
        }, {
          key: "_receiveResponse",
          value: function _receiveResponse(response) {
            var _this2 = this;
            if (response.status_code === 408 || response.status_code === 481) {
              this._eventHandlers.onDialogError(response);
            } else if (response.method === JsSIP_C.INVITE && response.status_code === 491) {
              if (this._reattempt) {
                if (response.status_code >= 200 && response.status_code < 300) {
                  this._eventHandlers.onSuccessResponse(response);
                } else if (response.status_code >= 300) {
                  this._eventHandlers.onErrorResponse(response);
                }
              } else {
                this._request.cseq = this._dialog.local_seqnum += 1;
                this._reattemptTimer = setTimeout(function() {
                  if (!_this2._dialog.isTerminated()) {
                    _this2._reattempt = true;
                    _this2.send();
                  }
                }, 1e3);
              }
            } else if (response.status_code >= 200 && response.status_code < 300) {
              this._eventHandlers.onSuccessResponse(response);
            } else if (response.status_code >= 300) {
              this._eventHandlers.onErrorResponse(response);
            }
          }
        }, {
          key: "request",
          get: function get() {
            return this._request;
          }
        }]);
        return DialogRequestSender;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Dialog.js
  var require_Dialog = __commonJS({
    "node_modules/jssip/lib-es5/Dialog.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var SIPMessage = require_SIPMessage();
      var JsSIP_C = require_Constants();
      var Transactions = require_Transactions();
      var Dialog_RequestSender = require_RequestSender2();
      var Utils = require_Utils();
      var logger = new Logger("Dialog");
      var C = {
        // Dialog states.
        STATUS_EARLY: 1,
        STATUS_CONFIRMED: 2,
        STATUS_TERMINATED: 3
      };
      module.exports = /* @__PURE__ */ function() {
        _createClass(Dialog, null, [{
          key: "C",
          // Expose C object.
          get: function get() {
            return C;
          }
        }]);
        function Dialog(owner, message, type) {
          var state = arguments.length > 3 && arguments[3] !== void 0 ? arguments[3] : C.STATUS_CONFIRMED;
          _classCallCheck(this, Dialog);
          this._owner = owner;
          this._ua = owner._ua;
          this._uac_pending_reply = false;
          this._uas_pending_reply = false;
          if (!message.hasHeader("contact")) {
            return {
              error: "unable to create a Dialog without Contact header field"
            };
          }
          if (message instanceof SIPMessage.IncomingResponse) {
            state = message.status_code < 200 ? C.STATUS_EARLY : C.STATUS_CONFIRMED;
          }
          var contact = message.parseHeader("contact");
          if (type === "UAS") {
            this._id = {
              call_id: message.call_id,
              local_tag: message.to_tag,
              remote_tag: message.from_tag,
              toString: function toString() {
                return this.call_id + this.local_tag + this.remote_tag;
              }
            };
            this._state = state;
            this._remote_seqnum = message.cseq;
            this._local_uri = message.parseHeader("to").uri;
            this._remote_uri = message.parseHeader("from").uri;
            this._remote_target = contact.uri;
            this._route_set = message.getHeaders("record-route");
            this._ack_seqnum = this._remote_seqnum;
          } else if (type === "UAC") {
            this._id = {
              call_id: message.call_id,
              local_tag: message.from_tag,
              remote_tag: message.to_tag,
              toString: function toString() {
                return this.call_id + this.local_tag + this.remote_tag;
              }
            };
            this._state = state;
            this._local_seqnum = message.cseq;
            this._local_uri = message.parseHeader("from").uri;
            this._remote_uri = message.parseHeader("to").uri;
            this._remote_target = contact.uri;
            this._route_set = message.getHeaders("record-route").reverse();
            this._ack_seqnum = null;
          }
          this._ua.newDialog(this);
          logger.debug("new ".concat(type, " dialog created with status ").concat(this._state === C.STATUS_EARLY ? "EARLY" : "CONFIRMED"));
        }
        _createClass(Dialog, [{
          key: "isTerminated",
          value: function isTerminated() {
            return this._status === C.STATUS_TERMINATED;
          }
        }, {
          key: "update",
          value: function update(message, type) {
            this._state = C.STATUS_CONFIRMED;
            logger.debug("dialog ".concat(this._id.toString(), "  changed to CONFIRMED state"));
            if (type === "UAC") {
              this._route_set = message.getHeaders("record-route").reverse();
            }
          }
        }, {
          key: "terminate",
          value: function terminate() {
            logger.debug("dialog ".concat(this._id.toString(), " deleted"));
            this._ua.destroyDialog(this);
            this._state = C.STATUS_TERMINATED;
          }
        }, {
          key: "sendRequest",
          value: function sendRequest(method) {
            var _this = this;
            var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var body = options.body || null;
            var request = this._createRequest(method, extraHeaders, body);
            eventHandlers.onAuthenticated = function() {
              _this._local_seqnum += 1;
            };
            var request_sender = new Dialog_RequestSender(this, request, eventHandlers);
            request_sender.send();
            return request;
          }
        }, {
          key: "receiveRequest",
          value: function receiveRequest(request) {
            if (!this._checkInDialogRequest(request)) {
              return;
            }
            if (request.method === JsSIP_C.ACK && this._ack_seqnum !== null) {
              this._ack_seqnum = null;
            } else if (request.method === JsSIP_C.INVITE) {
              this._ack_seqnum = request.cseq;
            }
            this._owner.receiveRequest(request);
          }
          // RFC 3261 12.2.1.1.
        }, {
          key: "_createRequest",
          value: function _createRequest(method, extraHeaders, body) {
            extraHeaders = Utils.cloneArray(extraHeaders);
            if (!this._local_seqnum) {
              this._local_seqnum = Math.floor(Math.random() * 1e4);
            }
            var cseq = method === JsSIP_C.CANCEL || method === JsSIP_C.ACK ? this._local_seqnum : this._local_seqnum += 1;
            var request = new SIPMessage.OutgoingRequest(method, this._remote_target, this._ua, {
              "cseq": cseq,
              "call_id": this._id.call_id,
              "from_uri": this._local_uri,
              "from_tag": this._id.local_tag,
              "to_uri": this._remote_uri,
              "to_tag": this._id.remote_tag,
              "route_set": this._route_set
            }, extraHeaders, body);
            return request;
          }
          // RFC 3261 12.2.2.
        }, {
          key: "_checkInDialogRequest",
          value: function _checkInDialogRequest(request) {
            var _this2 = this;
            if (!this._remote_seqnum) {
              this._remote_seqnum = request.cseq;
            } else if (request.cseq < this._remote_seqnum) {
              if (request.method === JsSIP_C.ACK) {
                if (this._ack_seqnum === null || request.cseq !== this._ack_seqnum) {
                  return false;
                }
              } else {
                request.reply(500);
                return false;
              }
            } else if (request.cseq > this._remote_seqnum) {
              this._remote_seqnum = request.cseq;
            }
            if (request.method === JsSIP_C.INVITE || request.method === JsSIP_C.UPDATE && request.body) {
              if (this._uac_pending_reply === true) {
                request.reply(491);
              } else if (this._uas_pending_reply === true) {
                var retryAfter = (Math.random() * 10 | 0) + 1;
                request.reply(500, null, ["Retry-After:".concat(retryAfter)]);
                return false;
              } else {
                this._uas_pending_reply = true;
                var stateChanged = function stateChanged2() {
                  if (request.server_transaction.state === Transactions.C.STATUS_ACCEPTED || request.server_transaction.state === Transactions.C.STATUS_COMPLETED || request.server_transaction.state === Transactions.C.STATUS_TERMINATED) {
                    request.server_transaction.removeListener("stateChanged", stateChanged2);
                    _this2._uas_pending_reply = false;
                  }
                };
                request.server_transaction.on("stateChanged", stateChanged);
              }
              if (request.hasHeader("contact")) {
                request.server_transaction.on("stateChanged", function() {
                  if (request.server_transaction.state === Transactions.C.STATUS_ACCEPTED) {
                    _this2._remote_target = request.parseHeader("contact").uri;
                  }
                });
              }
            } else if (request.method === JsSIP_C.NOTIFY) {
              if (request.hasHeader("contact")) {
                request.server_transaction.on("stateChanged", function() {
                  if (request.server_transaction.state === Transactions.C.STATUS_COMPLETED) {
                    _this2._remote_target = request.parseHeader("contact").uri;
                  }
                });
              }
            }
            return true;
          }
        }, {
          key: "id",
          get: function get() {
            return this._id;
          }
        }, {
          key: "local_seqnum",
          get: function get() {
            return this._local_seqnum;
          },
          set: function set(num) {
            this._local_seqnum = num;
          }
        }, {
          key: "owner",
          get: function get() {
            return this._owner;
          }
        }, {
          key: "uac_pending_reply",
          get: function get() {
            return this._uac_pending_reply;
          },
          set: function set(pending) {
            this._uac_pending_reply = pending;
          }
        }, {
          key: "uas_pending_reply",
          get: function get() {
            return this._uas_pending_reply;
          }
        }]);
        return Dialog;
      }();
    }
  });

  // node_modules/jssip/lib-es5/RTCSession/DTMF.js
  var require_DTMF = __commonJS({
    "node_modules/jssip/lib-es5/RTCSession/DTMF.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var Exceptions = require_Exceptions();
      var Utils = require_Utils();
      var logger = new Logger("RTCSession:DTMF");
      var C = {
        MIN_DURATION: 70,
        MAX_DURATION: 6e3,
        DEFAULT_DURATION: 100,
        MIN_INTER_TONE_GAP: 50,
        DEFAULT_INTER_TONE_GAP: 500
      };
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(DTMF, _EventEmitter);
        var _super = _createSuper(DTMF);
        function DTMF(session) {
          var _this;
          _classCallCheck(this, DTMF);
          _this = _super.call(this);
          _this._session = session;
          _this._direction = null;
          _this._tone = null;
          _this._duration = null;
          _this._request = null;
          return _this;
        }
        _createClass(DTMF, [{
          key: "send",
          value: function send(tone) {
            var _this2 = this;
            var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
            if (tone === void 0) {
              throw new TypeError("Not enough arguments");
            }
            this._direction = "outgoing";
            if (this._session.status !== this._session.C.STATUS_CONFIRMED && this._session.status !== this._session.C.STATUS_WAITING_FOR_ACK) {
              throw new Exceptions.InvalidStateError(this._session.status);
            }
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            this.eventHandlers = Utils.cloneObject(options.eventHandlers);
            if (typeof tone === "string") {
              tone = tone.toUpperCase();
            } else if (typeof tone === "number") {
              tone = tone.toString();
            } else {
              throw new TypeError("Invalid tone: ".concat(tone));
            }
            if (!tone.match(/^[0-9A-DR#*]$/)) {
              throw new TypeError("Invalid tone: ".concat(tone));
            } else {
              this._tone = tone;
            }
            this._duration = options.duration;
            extraHeaders.push("Content-Type: application/dtmf-relay");
            var body = "Signal=".concat(this._tone, "\r\n");
            body += "Duration=".concat(this._duration);
            this._session.newDTMF({
              originator: "local",
              dtmf: this,
              request: this._request
            });
            this._session.sendRequest(JsSIP_C.INFO, {
              extraHeaders,
              eventHandlers: {
                onSuccessResponse: function onSuccessResponse(response) {
                  _this2.emit("succeeded", {
                    originator: "remote",
                    response
                  });
                },
                onErrorResponse: function onErrorResponse(response) {
                  if (_this2.eventHandlers.onFailed) {
                    _this2.eventHandlers.onFailed();
                  }
                  _this2.emit("failed", {
                    originator: "remote",
                    response
                  });
                },
                onRequestTimeout: function onRequestTimeout() {
                  _this2._session.onRequestTimeout();
                },
                onTransportError: function onTransportError() {
                  _this2._session.onTransportError();
                },
                onDialogError: function onDialogError() {
                  _this2._session.onDialogError();
                }
              },
              body
            });
          }
        }, {
          key: "init_incoming",
          value: function init_incoming(request) {
            var reg_tone = /^(Signal\s*?=\s*?)([0-9A-D#*]{1})(\s)?.*/;
            var reg_duration = /^(Duration\s?=\s?)([0-9]{1,4})(\s)?.*/;
            this._direction = "incoming";
            this._request = request;
            request.reply(200);
            if (request.body) {
              var body = request.body.split("\n");
              if (body.length >= 1) {
                if (reg_tone.test(body[0])) {
                  this._tone = body[0].replace(reg_tone, "$2");
                }
              }
              if (body.length >= 2) {
                if (reg_duration.test(body[1])) {
                  this._duration = parseInt(body[1].replace(reg_duration, "$2"), 10);
                }
              }
            }
            if (!this._duration) {
              this._duration = C.DEFAULT_DURATION;
            }
            if (!this._tone) {
              logger.debug("invalid INFO DTMF received, discarded");
            } else {
              this._session.newDTMF({
                originator: "remote",
                dtmf: this,
                request
              });
            }
          }
        }, {
          key: "tone",
          get: function get() {
            return this._tone;
          }
        }, {
          key: "duration",
          get: function get() {
            return this._duration;
          }
        }]);
        return DTMF;
      }(EventEmitter);
      module.exports.C = C;
    }
  });

  // node_modules/jssip/lib-es5/RTCSession/Info.js
  var require_Info = __commonJS({
    "node_modules/jssip/lib-es5/RTCSession/Info.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var JsSIP_C = require_Constants();
      var Exceptions = require_Exceptions();
      var Utils = require_Utils();
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(Info, _EventEmitter);
        var _super = _createSuper(Info);
        function Info(session) {
          var _this;
          _classCallCheck(this, Info);
          _this = _super.call(this);
          _this._session = session;
          _this._direction = null;
          _this._contentType = null;
          _this._body = null;
          return _this;
        }
        _createClass(Info, [{
          key: "send",
          value: function send(contentType, body) {
            var _this2 = this;
            var options = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : {};
            this._direction = "outgoing";
            if (contentType === void 0) {
              throw new TypeError("Not enough arguments");
            }
            if (this._session.status !== this._session.C.STATUS_CONFIRMED && this._session.status !== this._session.C.STATUS_WAITING_FOR_ACK) {
              throw new Exceptions.InvalidStateError(this._session.status);
            }
            this._contentType = contentType;
            this._body = body;
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            extraHeaders.push("Content-Type: ".concat(contentType));
            this._session.newInfo({
              originator: "local",
              info: this,
              request: this.request
            });
            this._session.sendRequest(JsSIP_C.INFO, {
              extraHeaders,
              eventHandlers: {
                onSuccessResponse: function onSuccessResponse(response) {
                  _this2.emit("succeeded", {
                    originator: "remote",
                    response
                  });
                },
                onErrorResponse: function onErrorResponse(response) {
                  _this2.emit("failed", {
                    originator: "remote",
                    response
                  });
                },
                onTransportError: function onTransportError() {
                  _this2._session.onTransportError();
                },
                onRequestTimeout: function onRequestTimeout() {
                  _this2._session.onRequestTimeout();
                },
                onDialogError: function onDialogError() {
                  _this2._session.onDialogError();
                }
              },
              body
            });
          }
        }, {
          key: "init_incoming",
          value: function init_incoming(request) {
            this._direction = "incoming";
            this.request = request;
            request.reply(200);
            this._contentType = request.hasHeader("Content-Type") ? request.getHeader("Content-Type").toLowerCase() : void 0;
            this._body = request.body;
            this._session.newInfo({
              originator: "remote",
              info: this,
              request
            });
          }
        }, {
          key: "contentType",
          get: function get() {
            return this._contentType;
          }
        }, {
          key: "body",
          get: function get() {
            return this._body;
          }
        }]);
        return Info;
      }(EventEmitter);
    }
  });

  // node_modules/jssip/lib-es5/RTCSession/ReferNotifier.js
  var require_ReferNotifier = __commonJS({
    "node_modules/jssip/lib-es5/RTCSession/ReferNotifier.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var logger = new Logger("RTCSession:ReferNotifier");
      var C = {
        event_type: "refer",
        body_type: "message/sipfrag;version=2.0",
        expires: 300
      };
      module.exports = /* @__PURE__ */ function() {
        function ReferNotifier(session, id, expires) {
          _classCallCheck(this, ReferNotifier);
          this._session = session;
          this._id = id;
          this._expires = expires || C.expires;
          this._active = true;
          this.notify(100);
        }
        _createClass(ReferNotifier, [{
          key: "notify",
          value: function notify(code, reason) {
            logger.debug("notify()");
            if (this._active === false) {
              return;
            }
            reason = reason || JsSIP_C.REASON_PHRASE[code] || "";
            var state;
            if (code >= 200) {
              state = "terminated;reason=noresource";
            } else {
              state = "active;expires=".concat(this._expires);
            }
            this._session.sendRequest(JsSIP_C.NOTIFY, {
              extraHeaders: ["Event: ".concat(C.event_type, ";id=").concat(this._id), "Subscription-State: ".concat(state), "Content-Type: ".concat(C.body_type)],
              body: "SIP/2.0 ".concat(code, " ").concat(reason),
              eventHandlers: {
                // If a negative response is received, subscription is canceled.
                onErrorResponse: function onErrorResponse() {
                  this._active = false;
                }
              }
            });
          }
        }]);
        return ReferNotifier;
      }();
    }
  });

  // node_modules/jssip/lib-es5/RTCSession/ReferSubscriber.js
  var require_ReferSubscriber = __commonJS({
    "node_modules/jssip/lib-es5/RTCSession/ReferSubscriber.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var Grammar = require_Grammar();
      var Utils = require_Utils();
      var logger = new Logger("RTCSession:ReferSubscriber");
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(ReferSubscriber, _EventEmitter);
        var _super = _createSuper(ReferSubscriber);
        function ReferSubscriber(session) {
          var _this;
          _classCallCheck(this, ReferSubscriber);
          _this = _super.call(this);
          _this._id = null;
          _this._session = session;
          return _this;
        }
        _createClass(ReferSubscriber, [{
          key: "sendRefer",
          value: function sendRefer(target) {
            var _this2 = this;
            var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
            logger.debug("sendRefer()");
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            for (var event in eventHandlers) {
              if (Object.prototype.hasOwnProperty.call(eventHandlers, event)) {
                this.on(event, eventHandlers[event]);
              }
            }
            var replaces = null;
            if (options.replaces) {
              replaces = options.replaces._request.call_id;
              replaces += ";to-tag=".concat(options.replaces._to_tag);
              replaces += ";from-tag=".concat(options.replaces._from_tag);
              replaces = encodeURIComponent(replaces);
            }
            var referTo = "Refer-To: <".concat(target).concat(replaces ? "?Replaces=".concat(replaces) : "", ">");
            extraHeaders.push(referTo);
            if (!extraHeaders.some(function(header) {
              return header.toLowerCase().startsWith("referred-by:");
            })) {
              var referredBy = "Referred-By: <".concat(this._session._ua._configuration.uri._scheme, ":").concat(this._session._ua._configuration.uri._user, "@").concat(this._session._ua._configuration.uri._host, ">");
              extraHeaders.push(referredBy);
            }
            extraHeaders.push("Contact: ".concat(this._session.contact));
            var request = this._session.sendRequest(JsSIP_C.REFER, {
              extraHeaders,
              eventHandlers: {
                onSuccessResponse: function onSuccessResponse(response) {
                  _this2._requestSucceeded(response);
                },
                onErrorResponse: function onErrorResponse(response) {
                  _this2._requestFailed(response, JsSIP_C.causes.REJECTED);
                },
                onTransportError: function onTransportError() {
                  _this2._requestFailed(null, JsSIP_C.causes.CONNECTION_ERROR);
                },
                onRequestTimeout: function onRequestTimeout() {
                  _this2._requestFailed(null, JsSIP_C.causes.REQUEST_TIMEOUT);
                },
                onDialogError: function onDialogError() {
                  _this2._requestFailed(null, JsSIP_C.causes.DIALOG_ERROR);
                }
              }
            });
            this._id = request.cseq;
          }
        }, {
          key: "receiveNotify",
          value: function receiveNotify(request) {
            logger.debug("receiveNotify()");
            if (!request.body) {
              return;
            }
            var status_line = Grammar.parse(request.body.trim().split("\r\n", 1)[0], "Status_Line");
            if (status_line === -1) {
              logger.debug('receiveNotify() | error parsing NOTIFY body: "'.concat(request.body, '"'));
              return;
            }
            switch (true) {
              case /^100$/.test(status_line.status_code):
                this.emit("trying", {
                  request,
                  status_line
                });
                break;
              case /^1[0-9]{2}$/.test(status_line.status_code):
                this.emit("progress", {
                  request,
                  status_line
                });
                break;
              case /^2[0-9]{2}$/.test(status_line.status_code):
                this.emit("accepted", {
                  request,
                  status_line
                });
                break;
              default:
                this.emit("failed", {
                  request,
                  status_line
                });
                break;
            }
          }
        }, {
          key: "_requestSucceeded",
          value: function _requestSucceeded(response) {
            logger.debug("REFER succeeded");
            logger.debug('emit "requestSucceeded"');
            this.emit("requestSucceeded", {
              response
            });
          }
        }, {
          key: "_requestFailed",
          value: function _requestFailed(response, cause) {
            logger.debug("REFER failed");
            logger.debug('emit "requestFailed"');
            this.emit("requestFailed", {
              response: response || null,
              cause
            });
          }
        }, {
          key: "id",
          get: function get() {
            return this._id;
          }
        }]);
        return ReferSubscriber;
      }(EventEmitter);
    }
  });

  // node_modules/jssip/lib-es5/RTCSession.js
  var require_RTCSession = __commonJS({
    "node_modules/jssip/lib-es5/RTCSession.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e2) {
              throw _e2;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e3) {
          didErr = true;
          err = _e3;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var sdp_transform = require_lib();
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var Exceptions = require_Exceptions();
      var Transactions = require_Transactions();
      var Utils = require_Utils();
      var Timers = require_Timers();
      var SIPMessage = require_SIPMessage();
      var Dialog = require_Dialog();
      var RequestSender = require_RequestSender();
      var RTCSession_DTMF = require_DTMF();
      var RTCSession_Info = require_Info();
      var RTCSession_ReferNotifier = require_ReferNotifier();
      var RTCSession_ReferSubscriber = require_ReferSubscriber();
      var URI = require_URI();
      var logger = new Logger("RTCSession");
      var C = {
        // RTCSession states.
        STATUS_NULL: 0,
        STATUS_INVITE_SENT: 1,
        STATUS_1XX_RECEIVED: 2,
        STATUS_INVITE_RECEIVED: 3,
        STATUS_WAITING_FOR_ANSWER: 4,
        STATUS_ANSWERED: 5,
        STATUS_WAITING_FOR_ACK: 6,
        STATUS_CANCELED: 7,
        STATUS_TERMINATED: 8,
        STATUS_CONFIRMED: 9
      };
      var holdMediaTypes = ["audio", "video"];
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(RTCSession, _EventEmitter);
        var _super = _createSuper(RTCSession);
        _createClass(RTCSession, null, [{
          key: "C",
          /**
           * Expose C object.
           */
          get: function get() {
            return C;
          }
        }]);
        function RTCSession(ua) {
          var _this;
          _classCallCheck(this, RTCSession);
          logger.debug("new");
          _this = _super.call(this);
          _this._id = null;
          _this._ua = ua;
          _this._status = C.STATUS_NULL;
          _this._dialog = null;
          _this._earlyDialogs = {};
          _this._contact = null;
          _this._from_tag = null;
          _this._to_tag = null;
          _this._connection = null;
          _this._connectionPromiseQueue = Promise.resolve();
          _this._request = null;
          _this._is_canceled = false;
          _this._cancel_reason = "";
          _this._is_confirmed = false;
          _this._late_sdp = false;
          _this._rtcOfferConstraints = null;
          _this._rtcAnswerConstraints = null;
          _this._localMediaStream = null;
          _this._localMediaStreamLocallyGenerated = false;
          _this._rtcReady = true;
          _this._iceReady = false;
          _this._timers = {
            ackTimer: null,
            expiresTimer: null,
            invite2xxTimer: null,
            userNoAnswerTimer: null
          };
          _this._direction = null;
          _this._local_identity = null;
          _this._remote_identity = null;
          _this._start_time = null;
          _this._end_time = null;
          _this._tones = null;
          _this._audioMuted = false;
          _this._videoMuted = false;
          _this._localHold = false;
          _this._remoteHold = false;
          _this._sessionTimers = {
            enabled: _this._ua.configuration.session_timers,
            refreshMethod: _this._ua.configuration.session_timers_refresh_method,
            defaultExpires: JsSIP_C.SESSION_EXPIRES,
            currentExpires: null,
            running: false,
            refresher: false,
            timer: null
            // A setTimeout.
          };
          _this._referSubscribers = {};
          _this._data = {};
          return _this;
        }
        _createClass(RTCSession, [{
          key: "isInProgress",
          value: function isInProgress() {
            switch (this._status) {
              case C.STATUS_NULL:
              case C.STATUS_INVITE_SENT:
              case C.STATUS_1XX_RECEIVED:
              case C.STATUS_INVITE_RECEIVED:
              case C.STATUS_WAITING_FOR_ANSWER:
                return true;
              default:
                return false;
            }
          }
        }, {
          key: "isEstablished",
          value: function isEstablished() {
            switch (this._status) {
              case C.STATUS_ANSWERED:
              case C.STATUS_WAITING_FOR_ACK:
              case C.STATUS_CONFIRMED:
                return true;
              default:
                return false;
            }
          }
        }, {
          key: "isEnded",
          value: function isEnded() {
            switch (this._status) {
              case C.STATUS_CANCELED:
              case C.STATUS_TERMINATED:
                return true;
              default:
                return false;
            }
          }
        }, {
          key: "isMuted",
          value: function isMuted() {
            return {
              audio: this._audioMuted,
              video: this._videoMuted
            };
          }
        }, {
          key: "isOnHold",
          value: function isOnHold() {
            return {
              local: this._localHold,
              remote: this._remoteHold
            };
          }
        }, {
          key: "connect",
          value: function connect(target) {
            var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
            var initCallback = arguments.length > 2 ? arguments[2] : void 0;
            logger.debug("connect()");
            var originalTarget = target;
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var mediaConstraints = Utils.cloneObject(options.mediaConstraints, {
              audio: true,
              video: true
            });
            var mediaStream = options.mediaStream || null;
            var pcConfig = Utils.cloneObject(options.pcConfig, {
              iceServers: []
            });
            var rtcConstraints = options.rtcConstraints || null;
            var rtcOfferConstraints = options.rtcOfferConstraints || null;
            this._rtcOfferConstraints = rtcOfferConstraints;
            this._rtcAnswerConstraints = options.rtcAnswerConstraints || null;
            this._data = options.data || this._data;
            if (target === void 0) {
              throw new TypeError("Not enough arguments");
            }
            if (this._status !== C.STATUS_NULL) {
              throw new Exceptions.InvalidStateError(this._status);
            }
            if (!window.RTCPeerConnection) {
              throw new Exceptions.NotSupportedError("WebRTC not supported");
            }
            target = this._ua.normalizeTarget(target);
            if (!target) {
              throw new TypeError("Invalid target: ".concat(originalTarget));
            }
            if (this._sessionTimers.enabled) {
              if (Utils.isDecimal(options.sessionTimersExpires)) {
                if (options.sessionTimersExpires >= JsSIP_C.MIN_SESSION_EXPIRES) {
                  this._sessionTimers.defaultExpires = options.sessionTimersExpires;
                } else {
                  this._sessionTimers.defaultExpires = JsSIP_C.SESSION_EXPIRES;
                }
              }
            }
            for (var event in eventHandlers) {
              if (Object.prototype.hasOwnProperty.call(eventHandlers, event)) {
                this.on(event, eventHandlers[event]);
              }
            }
            this._from_tag = Utils.newTag();
            var anonymous = options.anonymous || false;
            var requestParams = {
              from_tag: this._from_tag
            };
            this._contact = this._ua.contact.toString({
              anonymous,
              outbound: true
            });
            if (anonymous) {
              requestParams.from_display_name = "Anonymous";
              requestParams.from_uri = new URI("sip", "anonymous", "anonymous.invalid");
              extraHeaders.push("P-Preferred-Identity: ".concat(this._ua.configuration.uri.toString()));
              extraHeaders.push("Privacy: id");
            } else if (options.fromUserName) {
              requestParams.from_uri = new URI("sip", options.fromUserName, this._ua.configuration.uri.host);
              extraHeaders.push("P-Preferred-Identity: ".concat(this._ua.configuration.uri.toString()));
            }
            if (options.fromDisplayName) {
              requestParams.from_display_name = options.fromDisplayName;
            }
            extraHeaders.push("Contact: ".concat(this._contact));
            extraHeaders.push("Content-Type: application/sdp");
            if (this._sessionTimers.enabled) {
              extraHeaders.push("Session-Expires: ".concat(this._sessionTimers.defaultExpires).concat(this._ua.configuration.session_timers_force_refresher ? ";refresher=uac" : ""));
            }
            this._request = new SIPMessage.InitialOutgoingInviteRequest(target, this._ua, requestParams, extraHeaders);
            this._id = this._request.call_id + this._from_tag;
            this._createRTCConnection(pcConfig, rtcConstraints);
            this._direction = "outgoing";
            this._local_identity = this._request.from;
            this._remote_identity = this._request.to;
            if (initCallback) {
              initCallback(this);
            }
            this._newRTCSession("local", this._request);
            this._sendInitialRequest(mediaConstraints, rtcOfferConstraints, mediaStream);
          }
        }, {
          key: "init_incoming",
          value: function init_incoming(request, initCallback) {
            var _this2 = this;
            logger.debug("init_incoming()");
            var expires;
            var contentType = request.hasHeader("Content-Type") ? request.getHeader("Content-Type").toLowerCase() : void 0;
            if (request.body && contentType !== "application/sdp") {
              request.reply(415);
              return;
            }
            this._status = C.STATUS_INVITE_RECEIVED;
            this._from_tag = request.from_tag;
            this._id = request.call_id + this._from_tag;
            this._request = request;
            this._contact = this._ua.contact.toString();
            if (request.hasHeader("expires")) {
              expires = request.getHeader("expires") * 1e3;
            }
            request.to_tag = Utils.newTag();
            if (!this._createDialog(request, "UAS", true)) {
              request.reply(500, "Missing Contact header field");
              return;
            }
            if (request.body) {
              this._late_sdp = false;
            } else {
              this._late_sdp = true;
            }
            this._status = C.STATUS_WAITING_FOR_ANSWER;
            this._timers.userNoAnswerTimer = setTimeout(function() {
              request.reply(408);
              _this2._failed("local", null, JsSIP_C.causes.NO_ANSWER);
            }, this._ua.configuration.no_answer_timeout);
            if (expires) {
              this._timers.expiresTimer = setTimeout(function() {
                if (_this2._status === C.STATUS_WAITING_FOR_ANSWER) {
                  request.reply(487);
                  _this2._failed("system", null, JsSIP_C.causes.EXPIRES);
                }
              }, expires);
            }
            this._direction = "incoming";
            this._local_identity = request.to;
            this._remote_identity = request.from;
            if (initCallback) {
              initCallback(this);
            }
            this._newRTCSession("remote", request);
            if (this._status === C.STATUS_TERMINATED) {
              return;
            }
            request.reply(180, null, ["Contact: ".concat(this._contact)]);
            this._progress("local", null);
          }
          /**
           * Answer the call.
           */
        }, {
          key: "answer",
          value: function answer() {
            var _this3 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            logger.debug("answer()");
            var request = this._request;
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var mediaConstraints = Utils.cloneObject(options.mediaConstraints);
            var mediaStream = options.mediaStream || null;
            var pcConfig = Utils.cloneObject(options.pcConfig, {
              iceServers: []
            });
            var rtcConstraints = options.rtcConstraints || null;
            var rtcAnswerConstraints = options.rtcAnswerConstraints || null;
            var rtcOfferConstraints = Utils.cloneObject(options.rtcOfferConstraints);
            var tracks;
            var peerHasAudioLine = false;
            var peerHasVideoLine = false;
            var peerOffersFullAudio = false;
            var peerOffersFullVideo = false;
            this._rtcAnswerConstraints = rtcAnswerConstraints;
            this._rtcOfferConstraints = options.rtcOfferConstraints || null;
            this._data = options.data || this._data;
            if (this._direction !== "incoming") {
              throw new Exceptions.NotSupportedError('"answer" not supported for outgoing RTCSession');
            }
            if (this._status !== C.STATUS_WAITING_FOR_ANSWER) {
              throw new Exceptions.InvalidStateError(this._status);
            }
            if (this._sessionTimers.enabled) {
              if (Utils.isDecimal(options.sessionTimersExpires)) {
                if (options.sessionTimersExpires >= JsSIP_C.MIN_SESSION_EXPIRES) {
                  this._sessionTimers.defaultExpires = options.sessionTimersExpires;
                } else {
                  this._sessionTimers.defaultExpires = JsSIP_C.SESSION_EXPIRES;
                }
              }
            }
            this._status = C.STATUS_ANSWERED;
            if (!this._createDialog(request, "UAS")) {
              request.reply(500, "Error creating dialog");
              return;
            }
            clearTimeout(this._timers.userNoAnswerTimer);
            extraHeaders.unshift("Contact: ".concat(this._contact));
            var sdp = request.parseSDP();
            if (!Array.isArray(sdp.media)) {
              sdp.media = [sdp.media];
            }
            var _iterator = _createForOfIteratorHelper(sdp.media), _step;
            try {
              for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                var m = _step.value;
                if (m.type === "audio") {
                  peerHasAudioLine = true;
                  if (!m.direction || m.direction === "sendrecv") {
                    peerOffersFullAudio = true;
                  }
                }
                if (m.type === "video") {
                  peerHasVideoLine = true;
                  if (!m.direction || m.direction === "sendrecv") {
                    peerOffersFullVideo = true;
                  }
                }
              }
            } catch (err) {
              _iterator.e(err);
            } finally {
              _iterator.f();
            }
            if (mediaStream && mediaConstraints.audio === false) {
              tracks = mediaStream.getAudioTracks();
              var _iterator2 = _createForOfIteratorHelper(tracks), _step2;
              try {
                for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
                  var track = _step2.value;
                  mediaStream.removeTrack(track);
                }
              } catch (err) {
                _iterator2.e(err);
              } finally {
                _iterator2.f();
              }
            }
            if (mediaStream && mediaConstraints.video === false) {
              tracks = mediaStream.getVideoTracks();
              var _iterator3 = _createForOfIteratorHelper(tracks), _step3;
              try {
                for (_iterator3.s(); !(_step3 = _iterator3.n()).done; ) {
                  var _track = _step3.value;
                  mediaStream.removeTrack(_track);
                }
              } catch (err) {
                _iterator3.e(err);
              } finally {
                _iterator3.f();
              }
            }
            if (!mediaStream && mediaConstraints.audio === void 0) {
              mediaConstraints.audio = peerOffersFullAudio;
            }
            if (!mediaStream && mediaConstraints.video === void 0) {
              mediaConstraints.video = peerOffersFullVideo;
            }
            if (!mediaStream && !peerHasAudioLine && !rtcOfferConstraints.offerToReceiveAudio) {
              mediaConstraints.audio = false;
            }
            if (!mediaStream && !peerHasVideoLine && !rtcOfferConstraints.offerToReceiveVideo) {
              mediaConstraints.video = false;
            }
            this._createRTCConnection(pcConfig, rtcConstraints);
            Promise.resolve().then(function() {
              if (mediaStream) {
                return mediaStream;
              } else if (mediaConstraints.audio || mediaConstraints.video) {
                _this3._localMediaStreamLocallyGenerated = true;
                return navigator.mediaDevices.getUserMedia(mediaConstraints)["catch"](function(error) {
                  if (_this3._status === C.STATUS_TERMINATED) {
                    throw new Error("terminated");
                  }
                  request.reply(480);
                  _this3._failed("local", null, JsSIP_C.causes.USER_DENIED_MEDIA_ACCESS);
                  logger.warn('emit "getusermediafailed" [error:%o]', error);
                  _this3.emit("getusermediafailed", error);
                  throw new Error("getUserMedia() failed");
                });
              }
            }).then(function(stream) {
              if (_this3._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              _this3._localMediaStream = stream;
              if (stream) {
                stream.getTracks().forEach(function(track2) {
                  _this3._connection.addTrack(track2, stream);
                });
              }
            }).then(function() {
              if (_this3._late_sdp) {
                return;
              }
              var e = {
                originator: "remote",
                type: "offer",
                sdp: request.body
              };
              logger.debug('emit "sdp"');
              _this3.emit("sdp", e);
              var offer = new RTCSessionDescription({
                type: "offer",
                sdp: e.sdp
              });
              _this3._connectionPromiseQueue = _this3._connectionPromiseQueue.then(function() {
                return _this3._connection.setRemoteDescription(offer);
              })["catch"](function(error) {
                request.reply(488);
                _this3._failed("system", null, JsSIP_C.causes.WEBRTC_ERROR);
                logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                _this3.emit("peerconnection:setremotedescriptionfailed", error);
                throw new Error("peerconnection.setRemoteDescription() failed");
              });
              return _this3._connectionPromiseQueue;
            }).then(function() {
              if (_this3._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              _this3._connecting(request);
              if (!_this3._late_sdp) {
                return _this3._createLocalDescription("answer", rtcAnswerConstraints)["catch"](function() {
                  request.reply(500);
                  throw new Error("_createLocalDescription() failed");
                });
              } else {
                return _this3._createLocalDescription("offer", _this3._rtcOfferConstraints)["catch"](function() {
                  request.reply(500);
                  throw new Error("_createLocalDescription() failed");
                });
              }
            }).then(function(desc) {
              if (_this3._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              _this3._handleSessionTimersInIncomingRequest(request, extraHeaders);
              request.reply(200, null, extraHeaders, desc, function() {
                _this3._status = C.STATUS_WAITING_FOR_ACK;
                _this3._setInvite2xxTimer(request, desc);
                _this3._setACKTimer();
                _this3._accepted("local");
              }, function() {
                _this3._failed("system", null, JsSIP_C.causes.CONNECTION_ERROR);
              });
            })["catch"](function(error) {
              if (_this3._status === C.STATUS_TERMINATED) {
                return;
              }
              logger.warn(error);
            });
          }
          /**
           * Terminate the call.
           */
        }, {
          key: "terminate",
          value: function terminate() {
            var _this4 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            logger.debug("terminate()");
            var cause = options.cause || JsSIP_C.causes.BYE;
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var body = options.body;
            var cancel_reason;
            var status_code = options.status_code;
            var reason_phrase = options.reason_phrase;
            if (this._status === C.STATUS_TERMINATED) {
              throw new Exceptions.InvalidStateError(this._status);
            }
            switch (this._status) {
              // - UAC -
              case C.STATUS_NULL:
              case C.STATUS_INVITE_SENT:
              case C.STATUS_1XX_RECEIVED:
                logger.debug("canceling session");
                if (status_code && (status_code < 200 || status_code >= 700)) {
                  throw new TypeError("Invalid status_code: ".concat(status_code));
                } else if (status_code) {
                  reason_phrase = reason_phrase || JsSIP_C.REASON_PHRASE[status_code] || "";
                  cancel_reason = "SIP ;cause=".concat(status_code, ' ;text="').concat(reason_phrase, '"');
                }
                if (this._status === C.STATUS_NULL || this._status === C.STATUS_INVITE_SENT) {
                  this._is_canceled = true;
                  this._cancel_reason = cancel_reason;
                } else if (this._status === C.STATUS_1XX_RECEIVED) {
                  this._request.cancel(cancel_reason);
                }
                this._status = C.STATUS_CANCELED;
                this._failed("local", null, JsSIP_C.causes.CANCELED);
                break;
              // - UAS -
              case C.STATUS_WAITING_FOR_ANSWER:
              case C.STATUS_ANSWERED:
                logger.debug("rejecting session");
                status_code = status_code || 480;
                if (status_code < 300 || status_code >= 700) {
                  throw new TypeError("Invalid status_code: ".concat(status_code));
                }
                this._request.reply(status_code, reason_phrase, extraHeaders, body);
                this._failed("local", null, JsSIP_C.causes.REJECTED);
                break;
              case C.STATUS_WAITING_FOR_ACK:
              case C.STATUS_CONFIRMED:
                logger.debug("terminating session");
                reason_phrase = options.reason_phrase || JsSIP_C.REASON_PHRASE[status_code] || "";
                if (status_code && (status_code < 200 || status_code >= 700)) {
                  throw new TypeError("Invalid status_code: ".concat(status_code));
                } else if (status_code) {
                  extraHeaders.push("Reason: SIP ;cause=".concat(status_code, '; text="').concat(reason_phrase, '"'));
                }
                if (this._status === C.STATUS_WAITING_FOR_ACK && this._direction === "incoming" && this._request.server_transaction.state !== Transactions.C.STATUS_TERMINATED) {
                  var dialog = this._dialog;
                  this.receiveRequest = function(_ref) {
                    var method = _ref.method;
                    if (method === JsSIP_C.ACK) {
                      _this4.sendRequest(JsSIP_C.BYE, {
                        extraHeaders,
                        body
                      });
                      dialog.terminate();
                    }
                  };
                  this._request.server_transaction.on("stateChanged", function() {
                    if (_this4._request.server_transaction.state === Transactions.C.STATUS_TERMINATED) {
                      _this4.sendRequest(JsSIP_C.BYE, {
                        extraHeaders,
                        body
                      });
                      dialog.terminate();
                    }
                  });
                  this._ended("local", null, cause);
                  this._dialog = dialog;
                  this._ua.newDialog(dialog);
                } else {
                  this.sendRequest(JsSIP_C.BYE, {
                    extraHeaders,
                    body
                  });
                  this._ended("local", null, cause);
                }
            }
          }
        }, {
          key: "sendDTMF",
          value: function sendDTMF(tones) {
            var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
            logger.debug("sendDTMF() | tones: %s", tones);
            var position = 0;
            var duration = options.duration || null;
            var interToneGap = options.interToneGap || null;
            var transportType = options.transportType || JsSIP_C.DTMF_TRANSPORT.INFO;
            if (tones === void 0) {
              throw new TypeError("Not enough arguments");
            }
            if (this._status !== C.STATUS_CONFIRMED && this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_1XX_RECEIVED) {
              throw new Exceptions.InvalidStateError(this._status);
            }
            if (transportType !== JsSIP_C.DTMF_TRANSPORT.INFO && transportType !== JsSIP_C.DTMF_TRANSPORT.RFC2833) {
              throw new TypeError("invalid transportType: ".concat(transportType));
            }
            if (typeof tones === "number") {
              tones = tones.toString();
            }
            if (!tones || typeof tones !== "string" || !tones.match(/^[0-9A-DR#*,]+$/i)) {
              throw new TypeError("Invalid tones: ".concat(tones));
            }
            if (duration && !Utils.isDecimal(duration)) {
              throw new TypeError("Invalid tone duration: ".concat(duration));
            } else if (!duration) {
              duration = RTCSession_DTMF.C.DEFAULT_DURATION;
            } else if (duration < RTCSession_DTMF.C.MIN_DURATION) {
              logger.debug('"duration" value is lower than the minimum allowed, setting it to '.concat(RTCSession_DTMF.C.MIN_DURATION, " milliseconds"));
              duration = RTCSession_DTMF.C.MIN_DURATION;
            } else if (duration > RTCSession_DTMF.C.MAX_DURATION) {
              logger.debug('"duration" value is greater than the maximum allowed, setting it to '.concat(RTCSession_DTMF.C.MAX_DURATION, " milliseconds"));
              duration = RTCSession_DTMF.C.MAX_DURATION;
            } else {
              duration = Math.abs(duration);
            }
            options.duration = duration;
            if (interToneGap && !Utils.isDecimal(interToneGap)) {
              throw new TypeError("Invalid interToneGap: ".concat(interToneGap));
            } else if (!interToneGap) {
              interToneGap = RTCSession_DTMF.C.DEFAULT_INTER_TONE_GAP;
            } else if (interToneGap < RTCSession_DTMF.C.MIN_INTER_TONE_GAP) {
              logger.debug('"interToneGap" value is lower than the minimum allowed, setting it to '.concat(RTCSession_DTMF.C.MIN_INTER_TONE_GAP, " milliseconds"));
              interToneGap = RTCSession_DTMF.C.MIN_INTER_TONE_GAP;
            } else {
              interToneGap = Math.abs(interToneGap);
            }
            if (transportType === JsSIP_C.DTMF_TRANSPORT.RFC2833) {
              var sender = this._getDTMFRTPSender();
              if (sender) {
                tones = sender.toneBuffer + tones;
                sender.insertDTMF(tones, duration, interToneGap);
              }
              return;
            }
            if (this._tones) {
              this._tones += tones;
              return;
            }
            this._tones = tones;
            _sendDTMF.call(this);
            function _sendDTMF() {
              var _this5 = this;
              var timeout;
              if (this._status === C.STATUS_TERMINATED || !this._tones || position >= this._tones.length) {
                this._tones = null;
                return;
              }
              var tone = this._tones[position];
              position += 1;
              if (tone === ",") {
                timeout = 2e3;
              } else {
                var dtmf = new RTCSession_DTMF(this);
                options.eventHandlers = {
                  onFailed: function onFailed() {
                    _this5._tones = null;
                  }
                };
                dtmf.send(tone, options);
                timeout = duration + interToneGap;
              }
              setTimeout(_sendDTMF.bind(this), timeout);
            }
          }
        }, {
          key: "sendInfo",
          value: function sendInfo(contentType, body) {
            var options = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : {};
            logger.debug("sendInfo()");
            if (this._status !== C.STATUS_CONFIRMED && this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_1XX_RECEIVED) {
              throw new Exceptions.InvalidStateError(this._status);
            }
            var info = new RTCSession_Info(this);
            info.send(contentType, body, options);
          }
          /**
           * Mute
           */
        }, {
          key: "mute",
          value: function mute() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {
              audio: true,
              video: false
            };
            logger.debug("mute()");
            var audioMuted = false, videoMuted = false;
            if (this._audioMuted === false && options.audio) {
              audioMuted = true;
              this._audioMuted = true;
              this._toggleMuteAudio(true);
            }
            if (this._videoMuted === false && options.video) {
              videoMuted = true;
              this._videoMuted = true;
              this._toggleMuteVideo(true);
            }
            if (audioMuted === true || videoMuted === true) {
              this._onmute({
                audio: audioMuted,
                video: videoMuted
              });
            }
          }
          /**
           * Unmute
           */
        }, {
          key: "unmute",
          value: function unmute() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {
              audio: true,
              video: true
            };
            logger.debug("unmute()");
            var audioUnMuted = false, videoUnMuted = false;
            if (this._audioMuted === true && options.audio) {
              audioUnMuted = true;
              this._audioMuted = false;
              if (this._localHold === false) {
                this._toggleMuteAudio(false);
              }
            }
            if (this._videoMuted === true && options.video) {
              videoUnMuted = true;
              this._videoMuted = false;
              if (this._localHold === false) {
                this._toggleMuteVideo(false);
              }
            }
            if (audioUnMuted === true || videoUnMuted === true) {
              this._onunmute({
                audio: audioUnMuted,
                video: videoUnMuted
              });
            }
          }
          /**
           * Hold
           */
        }, {
          key: "hold",
          value: function hold() {
            var _this6 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var done = arguments.length > 1 ? arguments[1] : void 0;
            logger.debug("hold()");
            if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
              return false;
            }
            if (this._localHold === true) {
              return false;
            }
            if (!this._isReadyToReOffer()) {
              return false;
            }
            this._localHold = true;
            this._onhold("local");
            var eventHandlers = {
              succeeded: function succeeded() {
                if (done) {
                  done();
                }
              },
              failed: function failed() {
                _this6.terminate({
                  cause: JsSIP_C.causes.WEBRTC_ERROR,
                  status_code: 500,
                  reason_phrase: "Hold Failed"
                });
              }
            };
            if (options.useUpdate) {
              this._sendUpdate({
                sdpOffer: true,
                eventHandlers,
                extraHeaders: options.extraHeaders
              });
            } else {
              this._sendReinvite({
                eventHandlers,
                extraHeaders: options.extraHeaders
              });
            }
            return true;
          }
        }, {
          key: "unhold",
          value: function unhold() {
            var _this7 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var done = arguments.length > 1 ? arguments[1] : void 0;
            logger.debug("unhold()");
            if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
              return false;
            }
            if (this._localHold === false) {
              return false;
            }
            if (!this._isReadyToReOffer()) {
              return false;
            }
            this._localHold = false;
            this._onunhold("local");
            var eventHandlers = {
              succeeded: function succeeded() {
                if (done) {
                  done();
                }
              },
              failed: function failed() {
                _this7.terminate({
                  cause: JsSIP_C.causes.WEBRTC_ERROR,
                  status_code: 500,
                  reason_phrase: "Unhold Failed"
                });
              }
            };
            if (options.useUpdate) {
              this._sendUpdate({
                sdpOffer: true,
                eventHandlers,
                extraHeaders: options.extraHeaders
              });
            } else {
              this._sendReinvite({
                eventHandlers,
                extraHeaders: options.extraHeaders
              });
            }
            return true;
          }
        }, {
          key: "renegotiate",
          value: function renegotiate() {
            var _this8 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var done = arguments.length > 1 ? arguments[1] : void 0;
            logger.debug("renegotiate()");
            var rtcOfferConstraints = options.rtcOfferConstraints || null;
            if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
              return false;
            }
            if (!this._isReadyToReOffer()) {
              return false;
            }
            var eventHandlers = {
              succeeded: function succeeded() {
                if (done) {
                  done();
                }
              },
              failed: function failed() {
                _this8.terminate({
                  cause: JsSIP_C.causes.WEBRTC_ERROR,
                  status_code: 500,
                  reason_phrase: "Media Renegotiation Failed"
                });
              }
            };
            this._setLocalMediaStatus();
            if (options.useUpdate) {
              this._sendUpdate({
                sdpOffer: true,
                eventHandlers,
                rtcOfferConstraints,
                extraHeaders: options.extraHeaders
              });
            } else {
              this._sendReinvite({
                eventHandlers,
                rtcOfferConstraints,
                extraHeaders: options.extraHeaders
              });
            }
            return true;
          }
          /**
           * Refer
           */
        }, {
          key: "refer",
          value: function refer(target, options) {
            var _this9 = this;
            logger.debug("refer()");
            var originalTarget = target;
            if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
              return false;
            }
            target = this._ua.normalizeTarget(target);
            if (!target) {
              throw new TypeError("Invalid target: ".concat(originalTarget));
            }
            var referSubscriber = new RTCSession_ReferSubscriber(this);
            referSubscriber.sendRefer(target, options);
            var id = referSubscriber.id;
            this._referSubscribers[id] = referSubscriber;
            referSubscriber.on("requestFailed", function() {
              delete _this9._referSubscribers[id];
            });
            referSubscriber.on("accepted", function() {
              delete _this9._referSubscribers[id];
            });
            referSubscriber.on("failed", function() {
              delete _this9._referSubscribers[id];
            });
            return referSubscriber;
          }
          /**
           * Send a generic in-dialog Request
           */
        }, {
          key: "sendRequest",
          value: function sendRequest(method, options) {
            logger.debug("sendRequest()");
            return this._dialog.sendRequest(method, options);
          }
          /**
           * In dialog Request Reception
           */
        }, {
          key: "receiveRequest",
          value: function receiveRequest(request) {
            var _this10 = this;
            logger.debug("receiveRequest()");
            if (request.method === JsSIP_C.CANCEL) {
              if (this._status === C.STATUS_WAITING_FOR_ANSWER || this._status === C.STATUS_ANSWERED) {
                this._status = C.STATUS_CANCELED;
                this._request.reply(487);
                this._failed("remote", request, JsSIP_C.causes.CANCELED);
              }
            } else {
              switch (request.method) {
                case JsSIP_C.ACK:
                  if (this._status !== C.STATUS_WAITING_FOR_ACK) {
                    return;
                  }
                  this._status = C.STATUS_CONFIRMED;
                  clearTimeout(this._timers.ackTimer);
                  clearTimeout(this._timers.invite2xxTimer);
                  if (this._late_sdp) {
                    if (!request.body) {
                      this.terminate({
                        cause: JsSIP_C.causes.MISSING_SDP,
                        status_code: 400
                      });
                      break;
                    }
                    var e = {
                      originator: "remote",
                      type: "answer",
                      sdp: request.body
                    };
                    logger.debug('emit "sdp"');
                    this.emit("sdp", e);
                    var answer = new RTCSessionDescription({
                      type: "answer",
                      sdp: e.sdp
                    });
                    this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                      return _this10._connection.setRemoteDescription(answer);
                    }).then(function() {
                      if (!_this10._is_confirmed) {
                        _this10._confirmed("remote", request);
                      }
                    })["catch"](function(error) {
                      _this10.terminate({
                        cause: JsSIP_C.causes.BAD_MEDIA_DESCRIPTION,
                        status_code: 488
                      });
                      logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                      _this10.emit("peerconnection:setremotedescriptionfailed", error);
                    });
                  } else if (!this._is_confirmed) {
                    this._confirmed("remote", request);
                  }
                  break;
                case JsSIP_C.BYE:
                  if (this._status === C.STATUS_CONFIRMED || this._status === C.STATUS_WAITING_FOR_ACK) {
                    request.reply(200);
                    this._ended("remote", request, JsSIP_C.causes.BYE);
                  } else if (this._status === C.STATUS_INVITE_RECEIVED || this._status === C.STATUS_WAITING_FOR_ANSWER) {
                    request.reply(200);
                    this._request.reply(487, "BYE Received");
                    this._ended("remote", request, JsSIP_C.causes.BYE);
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                case JsSIP_C.INVITE:
                  if (this._status === C.STATUS_CONFIRMED) {
                    if (request.hasHeader("replaces")) {
                      this._receiveReplaces(request);
                    } else {
                      this._receiveReinvite(request);
                    }
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                case JsSIP_C.INFO:
                  if (this._status === C.STATUS_1XX_RECEIVED || this._status === C.STATUS_WAITING_FOR_ANSWER || this._status === C.STATUS_ANSWERED || this._status === C.STATUS_WAITING_FOR_ACK || this._status === C.STATUS_CONFIRMED) {
                    var contentType = request.hasHeader("Content-Type") ? request.getHeader("Content-Type").toLowerCase() : void 0;
                    if (contentType && contentType.match(/^application\/dtmf-relay/i)) {
                      new RTCSession_DTMF(this).init_incoming(request);
                    } else if (contentType !== void 0) {
                      new RTCSession_Info(this).init_incoming(request);
                    } else {
                      request.reply(415);
                    }
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                case JsSIP_C.UPDATE:
                  if (this._status === C.STATUS_CONFIRMED) {
                    this._receiveUpdate(request);
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                case JsSIP_C.REFER:
                  if (this._status === C.STATUS_CONFIRMED) {
                    this._receiveRefer(request);
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                case JsSIP_C.NOTIFY:
                  if (this._status === C.STATUS_CONFIRMED) {
                    this._receiveNotify(request);
                  } else {
                    request.reply(403, "Wrong Status");
                  }
                  break;
                default:
                  request.reply(501);
              }
            }
          }
          /**
           * Session Callbacks
           */
        }, {
          key: "onTransportError",
          value: function onTransportError() {
            logger.warn("onTransportError()");
            if (this._status !== C.STATUS_TERMINATED) {
              this.terminate({
                status_code: 500,
                reason_phrase: JsSIP_C.causes.CONNECTION_ERROR,
                cause: JsSIP_C.causes.CONNECTION_ERROR
              });
            }
          }
        }, {
          key: "onRequestTimeout",
          value: function onRequestTimeout() {
            logger.warn("onRequestTimeout()");
            if (this._status !== C.STATUS_TERMINATED) {
              this.terminate({
                status_code: 408,
                reason_phrase: JsSIP_C.causes.REQUEST_TIMEOUT,
                cause: JsSIP_C.causes.REQUEST_TIMEOUT
              });
            }
          }
        }, {
          key: "onDialogError",
          value: function onDialogError() {
            logger.warn("onDialogError()");
            if (this._status !== C.STATUS_TERMINATED) {
              this.terminate({
                status_code: 500,
                reason_phrase: JsSIP_C.causes.DIALOG_ERROR,
                cause: JsSIP_C.causes.DIALOG_ERROR
              });
            }
          }
          // Called from DTMF handler.
        }, {
          key: "newDTMF",
          value: function newDTMF(data) {
            logger.debug("newDTMF()");
            this.emit("newDTMF", data);
          }
          // Called from Info handler.
        }, {
          key: "newInfo",
          value: function newInfo(data) {
            logger.debug("newInfo()");
            this.emit("newInfo", data);
          }
          /**
           * Check if RTCSession is ready for an outgoing re-INVITE or UPDATE with SDP.
           */
        }, {
          key: "_isReadyToReOffer",
          value: function _isReadyToReOffer() {
            if (!this._rtcReady) {
              logger.debug("_isReadyToReOffer() | internal WebRTC status not ready");
              return false;
            }
            if (!this._dialog) {
              logger.debug("_isReadyToReOffer() | session not established yet");
              return false;
            }
            if (this._dialog.uac_pending_reply === true || this._dialog.uas_pending_reply === true) {
              logger.debug("_isReadyToReOffer() | there is another INVITE/UPDATE transaction in progress");
              return false;
            }
            return true;
          }
        }, {
          key: "_close",
          value: function _close() {
            logger.debug("close()");
            if (this._localMediaStream && this._localMediaStreamLocallyGenerated) {
              logger.debug("close() | closing local MediaStream");
              Utils.closeMediaStream(this._localMediaStream);
            }
            if (this._status === C.STATUS_TERMINATED) {
              return;
            }
            this._status = C.STATUS_TERMINATED;
            if (this._connection) {
              try {
                this._connection.close();
              } catch (error) {
                logger.warn("close() | error closing the RTCPeerConnection: %o", error);
              }
            }
            for (var timer in this._timers) {
              if (Object.prototype.hasOwnProperty.call(this._timers, timer)) {
                clearTimeout(this._timers[timer]);
              }
            }
            clearTimeout(this._sessionTimers.timer);
            if (this._dialog) {
              this._dialog.terminate();
              delete this._dialog;
            }
            for (var dialog in this._earlyDialogs) {
              if (Object.prototype.hasOwnProperty.call(this._earlyDialogs, dialog)) {
                this._earlyDialogs[dialog].terminate();
                delete this._earlyDialogs[dialog];
              }
            }
            for (var subscriber in this._referSubscribers) {
              if (Object.prototype.hasOwnProperty.call(this._referSubscribers, subscriber)) {
                delete this._referSubscribers[subscriber];
              }
            }
            this._ua.destroyRTCSession(this);
          }
          /**
           * Private API.
           */
          /**
           * RFC3261 13.3.1.4
           * Response retransmissions cannot be accomplished by transaction layer
           *  since it is destroyed when receiving the first 2xx answer
           */
        }, {
          key: "_setInvite2xxTimer",
          value: function _setInvite2xxTimer(request, body) {
            var timeout = Timers.T1;
            function invite2xxRetransmission() {
              if (this._status !== C.STATUS_WAITING_FOR_ACK) {
                return;
              }
              request.reply(200, null, ["Contact: ".concat(this._contact)], body);
              if (timeout < Timers.T2) {
                timeout = timeout * 2;
                if (timeout > Timers.T2) {
                  timeout = Timers.T2;
                }
              }
              this._timers.invite2xxTimer = setTimeout(invite2xxRetransmission.bind(this), timeout);
            }
            this._timers.invite2xxTimer = setTimeout(invite2xxRetransmission.bind(this), timeout);
          }
          /**
           * RFC3261 14.2
           * If a UAS generates a 2xx response and never receives an ACK,
           *  it SHOULD generate a BYE to terminate the dialog.
           */
        }, {
          key: "_setACKTimer",
          value: function _setACKTimer() {
            var _this11 = this;
            this._timers.ackTimer = setTimeout(function() {
              if (_this11._status === C.STATUS_WAITING_FOR_ACK) {
                logger.debug("no ACK received, terminating the session");
                clearTimeout(_this11._timers.invite2xxTimer);
                _this11.sendRequest(JsSIP_C.BYE);
                _this11._ended("remote", null, JsSIP_C.causes.NO_ACK);
              }
            }, Timers.TIMER_H);
          }
        }, {
          key: "_createRTCConnection",
          value: function _createRTCConnection(pcConfig, rtcConstraints) {
            var _this12 = this;
            this._connection = new RTCPeerConnection(pcConfig, rtcConstraints);
            this._connection.addEventListener("iceconnectionstatechange", function() {
              var state = _this12._connection.iceConnectionState;
              if (state === "failed") {
                _this12.terminate({
                  cause: JsSIP_C.causes.RTP_TIMEOUT,
                  status_code: 408,
                  reason_phrase: JsSIP_C.causes.RTP_TIMEOUT
                });
              }
            });
            logger.debug('emit "peerconnection"');
            this.emit("peerconnection", {
              peerconnection: this._connection
            });
          }
        }, {
          key: "_createLocalDescription",
          value: function _createLocalDescription(type, constraints) {
            var _this13 = this;
            logger.debug("createLocalDescription()");
            if (type !== "offer" && type !== "answer") throw new Error('createLocalDescription() | invalid type "'.concat(type, '"'));
            var connection = this._connection;
            this._rtcReady = false;
            return Promise.resolve().then(function() {
              if (type === "offer") {
                return connection.createOffer(constraints)["catch"](function(error) {
                  logger.warn('emit "peerconnection:createofferfailed" [error:%o]', error);
                  _this13.emit("peerconnection:createofferfailed", error);
                  return Promise.reject(error);
                });
              } else {
                return connection.createAnswer(constraints)["catch"](function(error) {
                  logger.warn('emit "peerconnection:createanswerfailed" [error:%o]', error);
                  _this13.emit("peerconnection:createanswerfailed", error);
                  return Promise.reject(error);
                });
              }
            }).then(function(desc) {
              return connection.setLocalDescription(desc)["catch"](function(error) {
                _this13._rtcReady = true;
                logger.warn('emit "peerconnection:setlocaldescriptionfailed" [error:%o]', error);
                _this13.emit("peerconnection:setlocaldescriptionfailed", error);
                return Promise.reject(error);
              });
            }).then(function() {
              var iceRestart = constraints && constraints.iceRestart;
              if (connection.iceGatheringState === "complete" && !iceRestart || connection.iceGatheringState === "gathering" && _this13._iceReady) {
                _this13._rtcReady = true;
                var e = {
                  originator: "local",
                  type,
                  sdp: connection.localDescription.sdp
                };
                logger.debug('emit "sdp"');
                _this13.emit("sdp", e);
                return Promise.resolve(e.sdp);
              }
              return new Promise(function(resolve) {
                var finished = false;
                var iceCandidateListener;
                var iceGatheringStateListener;
                _this13._iceReady = false;
                var ready = function ready2() {
                  if (finished) {
                    return;
                  }
                  connection.removeEventListener("icecandidate", iceCandidateListener);
                  connection.removeEventListener("icegatheringstatechange", iceGatheringStateListener);
                  finished = true;
                  _this13._rtcReady = true;
                  _this13._iceReady = true;
                  var e2 = {
                    originator: "local",
                    type,
                    sdp: connection.localDescription.sdp
                  };
                  logger.debug('emit "sdp"');
                  _this13.emit("sdp", e2);
                  resolve(e2.sdp);
                };
                connection.addEventListener("icecandidate", iceCandidateListener = function iceCandidateListener2(event) {
                  var candidate = event.candidate;
                  if (candidate) {
                    _this13.emit("icecandidate", {
                      candidate,
                      ready
                    });
                  } else {
                    ready();
                  }
                });
                connection.addEventListener("icegatheringstatechange", iceGatheringStateListener = function iceGatheringStateListener2() {
                  if (connection.iceGatheringState === "complete") {
                    ready();
                  }
                });
              });
            });
          }
          /**
           * Dialog Management
           */
        }, {
          key: "_createDialog",
          value: function _createDialog(message, type, early) {
            var local_tag = type === "UAS" ? message.to_tag : message.from_tag;
            var remote_tag = type === "UAS" ? message.from_tag : message.to_tag;
            var id = message.call_id + local_tag + remote_tag;
            var early_dialog = this._earlyDialogs[id];
            if (early) {
              if (early_dialog) {
                return true;
              } else {
                early_dialog = new Dialog(this, message, type, Dialog.C.STATUS_EARLY);
                if (early_dialog.error) {
                  logger.debug(early_dialog.error);
                  this._failed("remote", message, JsSIP_C.causes.INTERNAL_ERROR);
                  return false;
                } else {
                  this._earlyDialogs[id] = early_dialog;
                  return true;
                }
              }
            } else {
              this._from_tag = message.from_tag;
              this._to_tag = message.to_tag;
              if (early_dialog) {
                early_dialog.update(message, type);
                this._dialog = early_dialog;
                delete this._earlyDialogs[id];
                return true;
              }
              var dialog = new Dialog(this, message, type);
              if (dialog.error) {
                logger.debug(dialog.error);
                this._failed("remote", message, JsSIP_C.causes.INTERNAL_ERROR);
                return false;
              } else {
                this._dialog = dialog;
                return true;
              }
            }
          }
          /**
           * In dialog INVITE Reception
           */
        }, {
          key: "_receiveReinvite",
          value: function _receiveReinvite(request) {
            var _this14 = this;
            logger.debug("receiveReinvite()");
            var contentType = request.hasHeader("Content-Type") ? request.getHeader("Content-Type").toLowerCase() : void 0;
            var data = {
              request,
              callback: void 0,
              reject: reject.bind(this)
            };
            var rejected = false;
            function reject() {
              var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
              rejected = true;
              var status_code = options.status_code || 403;
              var reason_phrase = options.reason_phrase || "";
              var extraHeaders = Utils.cloneArray(options.extraHeaders);
              if (this._status !== C.STATUS_CONFIRMED) {
                return false;
              }
              if (status_code < 300 || status_code >= 700) {
                throw new TypeError("Invalid status_code: ".concat(status_code));
              }
              request.reply(status_code, reason_phrase, extraHeaders);
            }
            this.emit("reinvite", data);
            if (rejected) {
              return;
            }
            this._late_sdp = false;
            if (!request.body) {
              this._late_sdp = true;
              if (this._remoteHold) {
                this._remoteHold = false;
                this._onunhold("remote");
              }
              this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                return _this14._createLocalDescription("offer", _this14._rtcOfferConstraints);
              }).then(function(sdp) {
                sendAnswer.call(_this14, sdp);
              })["catch"](function() {
                request.reply(500);
              });
              return;
            }
            if (contentType !== "application/sdp") {
              logger.debug("invalid Content-Type");
              request.reply(415);
              return;
            }
            this._processInDialogSdpOffer(request).then(function(desc) {
              if (_this14._status === C.STATUS_TERMINATED) {
                return;
              }
              sendAnswer.call(_this14, desc);
            })["catch"](function(error) {
              logger.warn(error);
            });
            function sendAnswer(desc) {
              var _this15 = this;
              var extraHeaders = ["Contact: ".concat(this._contact)];
              this._handleSessionTimersInIncomingRequest(request, extraHeaders);
              if (this._late_sdp) {
                desc = this._mangleOffer(desc);
              }
              request.reply(200, null, extraHeaders, desc, function() {
                _this15._status = C.STATUS_WAITING_FOR_ACK;
                _this15._setInvite2xxTimer(request, desc);
                _this15._setACKTimer();
              });
              if (typeof data.callback === "function") {
                data.callback();
              }
            }
          }
          /**
           * In dialog UPDATE Reception
           */
        }, {
          key: "_receiveUpdate",
          value: function _receiveUpdate(request) {
            var _this16 = this;
            logger.debug("receiveUpdate()");
            var contentType = request.hasHeader("Content-Type") ? request.getHeader("Content-Type").toLowerCase() : void 0;
            var data = {
              request,
              callback: void 0,
              reject: reject.bind(this)
            };
            var rejected = false;
            function reject() {
              var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
              rejected = true;
              var status_code = options.status_code || 403;
              var reason_phrase = options.reason_phrase || "";
              var extraHeaders = Utils.cloneArray(options.extraHeaders);
              if (this._status !== C.STATUS_CONFIRMED) {
                return false;
              }
              if (status_code < 300 || status_code >= 700) {
                throw new TypeError("Invalid status_code: ".concat(status_code));
              }
              request.reply(status_code, reason_phrase, extraHeaders);
            }
            this.emit("update", data);
            if (rejected) {
              return;
            }
            if (!request.body) {
              sendAnswer.call(this, null);
              return;
            }
            if (contentType !== "application/sdp") {
              logger.debug("invalid Content-Type");
              request.reply(415);
              return;
            }
            this._processInDialogSdpOffer(request).then(function(desc) {
              if (_this16._status === C.STATUS_TERMINATED) {
                return;
              }
              sendAnswer.call(_this16, desc);
            })["catch"](function(error) {
              logger.warn(error);
            });
            function sendAnswer(desc) {
              var extraHeaders = ["Contact: ".concat(this._contact)];
              this._handleSessionTimersInIncomingRequest(request, extraHeaders);
              request.reply(200, null, extraHeaders, desc);
              if (typeof data.callback === "function") {
                data.callback();
              }
            }
          }
        }, {
          key: "_processInDialogSdpOffer",
          value: function _processInDialogSdpOffer(request) {
            var _this17 = this;
            logger.debug("_processInDialogSdpOffer()");
            var sdp = request.parseSDP();
            var hold = false;
            var _iterator4 = _createForOfIteratorHelper(sdp.media), _step4;
            try {
              for (_iterator4.s(); !(_step4 = _iterator4.n()).done; ) {
                var m = _step4.value;
                if (holdMediaTypes.indexOf(m.type) === -1) {
                  continue;
                }
                var direction = m.direction || sdp.direction || "sendrecv";
                if (direction === "sendonly" || direction === "inactive") {
                  hold = true;
                } else {
                  hold = false;
                  break;
                }
              }
            } catch (err) {
              _iterator4.e(err);
            } finally {
              _iterator4.f();
            }
            var e = {
              originator: "remote",
              type: "offer",
              sdp: request.body
            };
            logger.debug('emit "sdp"');
            this.emit("sdp", e);
            var offer = new RTCSessionDescription({
              type: "offer",
              sdp: e.sdp
            });
            this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
              if (_this17._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              return _this17._connection.setRemoteDescription(offer)["catch"](function(error) {
                request.reply(488);
                logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                _this17.emit("peerconnection:setremotedescriptionfailed", error);
                throw error;
              });
            }).then(function() {
              if (_this17._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              if (_this17._remoteHold === true && hold === false) {
                _this17._remoteHold = false;
                _this17._onunhold("remote");
              } else if (_this17._remoteHold === false && hold === true) {
                _this17._remoteHold = true;
                _this17._onhold("remote");
              }
            }).then(function() {
              if (_this17._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              return _this17._createLocalDescription("answer", _this17._rtcAnswerConstraints)["catch"](function(error) {
                request.reply(500);
                logger.warn('emit "peerconnection:createtelocaldescriptionfailed" [error:%o]', error);
                throw error;
              });
            })["catch"](function(error) {
              logger.warn("_processInDialogSdpOffer() failed [error: %o]", error);
            });
            return this._connectionPromiseQueue;
          }
          /**
           * In dialog Refer Reception
           */
        }, {
          key: "_receiveRefer",
          value: function _receiveRefer(request) {
            var _this18 = this;
            logger.debug("receiveRefer()");
            if (!request.refer_to) {
              logger.debug("no Refer-To header field present in REFER");
              request.reply(400);
              return;
            }
            if (request.refer_to.uri.scheme !== JsSIP_C.SIP) {
              logger.debug("Refer-To header field points to a non-SIP URI scheme");
              request.reply(416);
              return;
            }
            request.reply(202);
            var notifier = new RTCSession_ReferNotifier(this, request.cseq);
            logger.debug('emit "refer"');
            this.emit("refer", {
              request,
              accept: function accept(initCallback, options) {
                _accept.call(_this18, initCallback, options);
              },
              reject: function reject() {
                _reject.call(_this18);
              }
            });
            function _accept(initCallback) {
              var options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {};
              initCallback = typeof initCallback === "function" ? initCallback : null;
              if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
                return false;
              }
              var session = new RTCSession(this._ua);
              session.on("progress", function(_ref2) {
                var response = _ref2.response;
                notifier.notify(response.status_code, response.reason_phrase);
              });
              session.on("accepted", function(_ref3) {
                var response = _ref3.response;
                notifier.notify(response.status_code, response.reason_phrase);
              });
              session.on("_failed", function(_ref4) {
                var message = _ref4.message, cause = _ref4.cause;
                if (message) {
                  notifier.notify(message.status_code, message.reason_phrase);
                } else {
                  notifier.notify(487, cause);
                }
              });
              if (request.refer_to.uri.hasHeader("replaces")) {
                var replaces = decodeURIComponent(request.refer_to.uri.getHeader("replaces"));
                options.extraHeaders = Utils.cloneArray(options.extraHeaders);
                options.extraHeaders.push("Replaces: ".concat(replaces));
              }
              session.connect(request.refer_to.uri.toAor(), options, initCallback);
            }
            function _reject() {
              notifier.notify(603);
            }
          }
          /**
           * In dialog Notify Reception
           */
        }, {
          key: "_receiveNotify",
          value: function _receiveNotify(request) {
            logger.debug("receiveNotify()");
            if (!request.event) {
              request.reply(400);
            }
            switch (request.event.event) {
              case "refer": {
                var id;
                var referSubscriber;
                if (request.event.params && request.event.params.id) {
                  id = request.event.params.id;
                  referSubscriber = this._referSubscribers[id];
                } else if (Object.keys(this._referSubscribers).length === 1) {
                  referSubscriber = this._referSubscribers[Object.keys(this._referSubscribers)[0]];
                } else {
                  request.reply(400, "Missing event id parameter");
                  return;
                }
                if (!referSubscriber) {
                  request.reply(481, "Subscription does not exist");
                  return;
                }
                referSubscriber.receiveNotify(request);
                request.reply(200);
                break;
              }
              default: {
                request.reply(489);
              }
            }
          }
          /**
           * INVITE with Replaces Reception
           */
        }, {
          key: "_receiveReplaces",
          value: function _receiveReplaces(request) {
            var _this20 = this;
            logger.debug("receiveReplaces()");
            function _accept2(initCallback) {
              var _this19 = this;
              if (this._status !== C.STATUS_WAITING_FOR_ACK && this._status !== C.STATUS_CONFIRMED) {
                return false;
              }
              var session = new RTCSession(this._ua);
              session.on("confirmed", function() {
                _this19.terminate();
              });
              session.init_incoming(request, initCallback);
            }
            function _reject2() {
              logger.debug("Replaced INVITE rejected by the user");
              request.reply(486);
            }
            this.emit("replaces", {
              request,
              accept: function accept(initCallback) {
                _accept2.call(_this20, initCallback);
              },
              reject: function reject() {
                _reject2.call(_this20);
              }
            });
          }
          /**
           * Initial Request Sender
           */
        }, {
          key: "_sendInitialRequest",
          value: function _sendInitialRequest(mediaConstraints, rtcOfferConstraints, mediaStream) {
            var _this21 = this;
            var request_sender = new RequestSender(this._ua, this._request, {
              onRequestTimeout: function onRequestTimeout() {
                _this21.onRequestTimeout();
              },
              onTransportError: function onTransportError() {
                _this21.onTransportError();
              },
              // Update the request on authentication.
              onAuthenticated: function onAuthenticated(request) {
                _this21._request = request;
              },
              onReceiveResponse: function onReceiveResponse(response) {
                _this21._receiveInviteResponse(response);
              }
            });
            Promise.resolve().then(function() {
              if (mediaStream) {
                return mediaStream;
              } else if (mediaConstraints.audio || mediaConstraints.video) {
                _this21._localMediaStreamLocallyGenerated = true;
                return navigator.mediaDevices.getUserMedia(mediaConstraints)["catch"](function(error) {
                  if (_this21._status === C.STATUS_TERMINATED) {
                    throw new Error("terminated");
                  }
                  _this21._failed("local", null, JsSIP_C.causes.USER_DENIED_MEDIA_ACCESS);
                  logger.warn('emit "getusermediafailed" [error:%o]', error);
                  _this21.emit("getusermediafailed", error);
                  throw error;
                });
              }
            }).then(function(stream) {
              if (_this21._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              _this21._localMediaStream = stream;
              if (stream) {
                stream.getTracks().forEach(function(track) {
                  _this21._connection.addTrack(track, stream);
                });
              }
              _this21._connecting(_this21._request);
              return _this21._createLocalDescription("offer", rtcOfferConstraints)["catch"](function(error) {
                _this21._failed("local", null, JsSIP_C.causes.WEBRTC_ERROR);
                throw error;
              });
            }).then(function(desc) {
              if (_this21._is_canceled || _this21._status === C.STATUS_TERMINATED) {
                throw new Error("terminated");
              }
              _this21._request.body = desc;
              _this21._status = C.STATUS_INVITE_SENT;
              logger.debug('emit "sending" [request:%o]', _this21._request);
              _this21.emit("sending", {
                request: _this21._request
              });
              request_sender.send();
            })["catch"](function(error) {
              if (_this21._status === C.STATUS_TERMINATED) {
                return;
              }
              logger.warn(error);
            });
          }
          /**
           * Get DTMF RTCRtpSender.
           */
        }, {
          key: "_getDTMFRTPSender",
          value: function _getDTMFRTPSender() {
            var sender = this._connection.getSenders().find(function(rtpSender) {
              return rtpSender.track && rtpSender.track.kind === "audio";
            });
            if (!(sender && sender.dtmf)) {
              logger.warn("sendDTMF() | no local audio track to send DTMF with");
              return;
            }
            return sender.dtmf;
          }
          /**
           * Reception of Response for Initial INVITE
           */
        }, {
          key: "_receiveInviteResponse",
          value: function _receiveInviteResponse(response) {
            var _this22 = this;
            logger.debug("receiveInviteResponse()");
            if (this._dialog && response.status_code >= 200 && response.status_code <= 299) {
              if (this._dialog.id.call_id === response.call_id && this._dialog.id.local_tag === response.from_tag && this._dialog.id.remote_tag === response.to_tag) {
                this.sendRequest(JsSIP_C.ACK);
                return;
              } else {
                var dialog = new Dialog(this, response, "UAC");
                if (dialog.error !== void 0) {
                  logger.debug(dialog.error);
                  return;
                }
                this.sendRequest(JsSIP_C.ACK);
                this.sendRequest(JsSIP_C.BYE);
                return;
              }
            }
            if (this._is_canceled) {
              if (response.status_code >= 100 && response.status_code < 200) {
                this._request.cancel(this._cancel_reason);
              } else if (response.status_code >= 200 && response.status_code < 299) {
                this._acceptAndTerminate(response);
              }
              return;
            }
            if (this._status !== C.STATUS_INVITE_SENT && this._status !== C.STATUS_1XX_RECEIVED) {
              return;
            }
            switch (true) {
              case /^100$/.test(response.status_code):
                this._status = C.STATUS_1XX_RECEIVED;
                break;
              case /^1[0-9]{2}$/.test(response.status_code): {
                if (!response.to_tag) {
                  logger.debug("1xx response received without to tag");
                  break;
                }
                if (response.hasHeader("contact")) {
                  if (!this._createDialog(response, "UAC", true)) {
                    break;
                  }
                }
                this._status = C.STATUS_1XX_RECEIVED;
                if (!response.body) {
                  this._progress("remote", response);
                  break;
                }
                var e = {
                  originator: "remote",
                  type: "answer",
                  sdp: response.body
                };
                logger.debug('emit "sdp"');
                this.emit("sdp", e);
                var answer = new RTCSessionDescription({
                  type: "answer",
                  sdp: e.sdp
                });
                this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                  return _this22._connection.setRemoteDescription(answer);
                }).then(function() {
                  return _this22._progress("remote", response);
                })["catch"](function(error) {
                  logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                  _this22.emit("peerconnection:setremotedescriptionfailed", error);
                });
                break;
              }
              case /^2[0-9]{2}$/.test(response.status_code): {
                this._status = C.STATUS_CONFIRMED;
                if (!response.body) {
                  this._acceptAndTerminate(response, 400, JsSIP_C.causes.MISSING_SDP);
                  this._failed("remote", response, JsSIP_C.causes.BAD_MEDIA_DESCRIPTION);
                  break;
                }
                if (!this._createDialog(response, "UAC")) {
                  break;
                }
                var _e = {
                  originator: "remote",
                  type: "answer",
                  sdp: response.body
                };
                logger.debug('emit "sdp"');
                this.emit("sdp", _e);
                var _answer = new RTCSessionDescription({
                  type: "answer",
                  sdp: _e.sdp
                });
                this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                  if (_this22._connection.signalingState === "stable") {
                    return _this22._connection.createOffer(_this22._rtcOfferConstraints).then(function(offer) {
                      return _this22._connection.setLocalDescription(offer);
                    })["catch"](function(error) {
                      _this22._acceptAndTerminate(response, 500, error.toString());
                      _this22._failed("local", response, JsSIP_C.causes.WEBRTC_ERROR);
                    });
                  }
                }).then(function() {
                  _this22._connection.setRemoteDescription(_answer).then(function() {
                    _this22._handleSessionTimersInIncomingResponse(response);
                    _this22._accepted("remote", response);
                    _this22.sendRequest(JsSIP_C.ACK);
                    _this22._confirmed("local", null);
                  })["catch"](function(error) {
                    _this22._acceptAndTerminate(response, 488, "Not Acceptable Here");
                    _this22._failed("remote", response, JsSIP_C.causes.BAD_MEDIA_DESCRIPTION);
                    logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                    _this22.emit("peerconnection:setremotedescriptionfailed", error);
                  });
                });
                break;
              }
              default: {
                var cause = Utils.sipErrorCause(response.status_code);
                this._failed("remote", response, cause);
              }
            }
          }
          /**
           * Send Re-INVITE
           */
        }, {
          key: "_sendReinvite",
          value: function _sendReinvite() {
            var _this23 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            logger.debug("sendReinvite()");
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var rtcOfferConstraints = options.rtcOfferConstraints || this._rtcOfferConstraints || null;
            var succeeded = false;
            extraHeaders.push("Contact: ".concat(this._contact));
            extraHeaders.push("Content-Type: application/sdp");
            if (this._sessionTimers.running) {
              extraHeaders.push("Session-Expires: ".concat(this._sessionTimers.currentExpires, ";refresher=").concat(this._sessionTimers.refresher ? "uac" : "uas"));
            }
            this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
              return _this23._createLocalDescription("offer", rtcOfferConstraints);
            }).then(function(sdp) {
              sdp = _this23._mangleOffer(sdp);
              var e = {
                originator: "local",
                type: "offer",
                sdp
              };
              logger.debug('emit "sdp"');
              _this23.emit("sdp", e);
              _this23.sendRequest(JsSIP_C.INVITE, {
                extraHeaders,
                body: sdp,
                eventHandlers: {
                  onSuccessResponse: function onSuccessResponse(response) {
                    onSucceeded.call(_this23, response);
                    succeeded = true;
                  },
                  onErrorResponse: function onErrorResponse(response) {
                    onFailed.call(_this23, response);
                  },
                  onTransportError: function onTransportError() {
                    _this23.onTransportError();
                  },
                  onRequestTimeout: function onRequestTimeout() {
                    _this23.onRequestTimeout();
                  },
                  onDialogError: function onDialogError() {
                    _this23.onDialogError();
                  }
                }
              });
            })["catch"](function() {
              onFailed();
            });
            function onSucceeded(response) {
              var _this24 = this;
              if (this._status === C.STATUS_TERMINATED) {
                return;
              }
              this.sendRequest(JsSIP_C.ACK);
              if (succeeded) {
                return;
              }
              this._handleSessionTimersInIncomingResponse(response);
              if (!response.body) {
                onFailed.call(this);
                return;
              } else if (!response.hasHeader("Content-Type") || response.getHeader("Content-Type").toLowerCase() !== "application/sdp") {
                onFailed.call(this);
                return;
              }
              var e = {
                originator: "remote",
                type: "answer",
                sdp: response.body
              };
              logger.debug('emit "sdp"');
              this.emit("sdp", e);
              var answer = new RTCSessionDescription({
                type: "answer",
                sdp: e.sdp
              });
              this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                return _this24._connection.setRemoteDescription(answer);
              }).then(function() {
                if (eventHandlers.succeeded) {
                  eventHandlers.succeeded(response);
                }
              })["catch"](function(error) {
                onFailed.call(_this24);
                logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                _this24.emit("peerconnection:setremotedescriptionfailed", error);
              });
            }
            function onFailed(response) {
              if (eventHandlers.failed) {
                eventHandlers.failed(response);
              }
            }
          }
          /**
           * Send UPDATE
           */
        }, {
          key: "_sendUpdate",
          value: function _sendUpdate() {
            var _this25 = this;
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            logger.debug("sendUpdate()");
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var rtcOfferConstraints = options.rtcOfferConstraints || this._rtcOfferConstraints || null;
            var sdpOffer = options.sdpOffer || false;
            var succeeded = false;
            extraHeaders.push("Contact: ".concat(this._contact));
            if (this._sessionTimers.running) {
              extraHeaders.push("Session-Expires: ".concat(this._sessionTimers.currentExpires, ";refresher=").concat(this._sessionTimers.refresher ? "uac" : "uas"));
            }
            if (sdpOffer) {
              extraHeaders.push("Content-Type: application/sdp");
              this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                return _this25._createLocalDescription("offer", rtcOfferConstraints);
              }).then(function(sdp) {
                sdp = _this25._mangleOffer(sdp);
                var e = {
                  originator: "local",
                  type: "offer",
                  sdp
                };
                logger.debug('emit "sdp"');
                _this25.emit("sdp", e);
                _this25.sendRequest(JsSIP_C.UPDATE, {
                  extraHeaders,
                  body: sdp,
                  eventHandlers: {
                    onSuccessResponse: function onSuccessResponse(response) {
                      onSucceeded.call(_this25, response);
                      succeeded = true;
                    },
                    onErrorResponse: function onErrorResponse(response) {
                      onFailed.call(_this25, response);
                    },
                    onTransportError: function onTransportError() {
                      _this25.onTransportError();
                    },
                    onRequestTimeout: function onRequestTimeout() {
                      _this25.onRequestTimeout();
                    },
                    onDialogError: function onDialogError() {
                      _this25.onDialogError();
                    }
                  }
                });
              })["catch"](function() {
                onFailed.call(_this25);
              });
            } else {
              this.sendRequest(JsSIP_C.UPDATE, {
                extraHeaders,
                eventHandlers: {
                  onSuccessResponse: function onSuccessResponse(response) {
                    onSucceeded.call(_this25, response);
                  },
                  onErrorResponse: function onErrorResponse(response) {
                    onFailed.call(_this25, response);
                  },
                  onTransportError: function onTransportError() {
                    _this25.onTransportError();
                  },
                  onRequestTimeout: function onRequestTimeout() {
                    _this25.onRequestTimeout();
                  },
                  onDialogError: function onDialogError() {
                    _this25.onDialogError();
                  }
                }
              });
            }
            function onSucceeded(response) {
              var _this26 = this;
              if (this._status === C.STATUS_TERMINATED) {
                return;
              }
              if (succeeded) {
                return;
              }
              this._handleSessionTimersInIncomingResponse(response);
              if (sdpOffer) {
                if (!response.body) {
                  onFailed.call(this);
                  return;
                } else if (!response.hasHeader("Content-Type") || response.getHeader("Content-Type").toLowerCase() !== "application/sdp") {
                  onFailed.call(this);
                  return;
                }
                var e = {
                  originator: "remote",
                  type: "answer",
                  sdp: response.body
                };
                logger.debug('emit "sdp"');
                this.emit("sdp", e);
                var answer = new RTCSessionDescription({
                  type: "answer",
                  sdp: e.sdp
                });
                this._connectionPromiseQueue = this._connectionPromiseQueue.then(function() {
                  return _this26._connection.setRemoteDescription(answer);
                }).then(function() {
                  if (eventHandlers.succeeded) {
                    eventHandlers.succeeded(response);
                  }
                })["catch"](function(error) {
                  onFailed.call(_this26);
                  logger.warn('emit "peerconnection:setremotedescriptionfailed" [error:%o]', error);
                  _this26.emit("peerconnection:setremotedescriptionfailed", error);
                });
              } else if (eventHandlers.succeeded) {
                eventHandlers.succeeded(response);
              }
            }
            function onFailed(response) {
              if (eventHandlers.failed) {
                eventHandlers.failed(response);
              }
            }
          }
        }, {
          key: "_acceptAndTerminate",
          value: function _acceptAndTerminate(response, status_code, reason_phrase) {
            logger.debug("acceptAndTerminate()");
            var extraHeaders = [];
            if (status_code) {
              reason_phrase = reason_phrase || JsSIP_C.REASON_PHRASE[status_code] || "";
              extraHeaders.push("Reason: SIP ;cause=".concat(status_code, '; text="').concat(reason_phrase, '"'));
            }
            if (this._dialog || this._createDialog(response, "UAC")) {
              this.sendRequest(JsSIP_C.ACK);
              this.sendRequest(JsSIP_C.BYE, {
                extraHeaders
              });
            }
            this._status = C.STATUS_TERMINATED;
          }
          /**
           * Correctly set the SDP direction attributes if the call is on local hold
           */
        }, {
          key: "_mangleOffer",
          value: function _mangleOffer(sdp) {
            if (!this._localHold && !this._remoteHold) {
              return sdp;
            }
            sdp = sdp_transform.parse(sdp);
            if (this._localHold && !this._remoteHold) {
              logger.debug("mangleOffer() | me on hold, mangling offer");
              var _iterator5 = _createForOfIteratorHelper(sdp.media), _step5;
              try {
                for (_iterator5.s(); !(_step5 = _iterator5.n()).done; ) {
                  var m = _step5.value;
                  if (holdMediaTypes.indexOf(m.type) === -1) {
                    continue;
                  }
                  if (!m.direction) {
                    m.direction = "sendonly";
                  } else if (m.direction === "sendrecv") {
                    m.direction = "sendonly";
                  } else if (m.direction === "recvonly") {
                    m.direction = "inactive";
                  }
                }
              } catch (err) {
                _iterator5.e(err);
              } finally {
                _iterator5.f();
              }
            } else if (this._localHold && this._remoteHold) {
              logger.debug("mangleOffer() | both on hold, mangling offer");
              var _iterator6 = _createForOfIteratorHelper(sdp.media), _step6;
              try {
                for (_iterator6.s(); !(_step6 = _iterator6.n()).done; ) {
                  var _m = _step6.value;
                  if (holdMediaTypes.indexOf(_m.type) === -1) {
                    continue;
                  }
                  _m.direction = "inactive";
                }
              } catch (err) {
                _iterator6.e(err);
              } finally {
                _iterator6.f();
              }
            } else if (this._remoteHold) {
              logger.debug("mangleOffer() | remote on hold, mangling offer");
              var _iterator7 = _createForOfIteratorHelper(sdp.media), _step7;
              try {
                for (_iterator7.s(); !(_step7 = _iterator7.n()).done; ) {
                  var _m2 = _step7.value;
                  if (holdMediaTypes.indexOf(_m2.type) === -1) {
                    continue;
                  }
                  if (!_m2.direction) {
                    _m2.direction = "recvonly";
                  } else if (_m2.direction === "sendrecv") {
                    _m2.direction = "recvonly";
                  } else if (_m2.direction === "recvonly") {
                    _m2.direction = "inactive";
                  }
                }
              } catch (err) {
                _iterator7.e(err);
              } finally {
                _iterator7.f();
              }
            }
            return sdp_transform.write(sdp);
          }
        }, {
          key: "_setLocalMediaStatus",
          value: function _setLocalMediaStatus() {
            var enableAudio = true, enableVideo = true;
            if (this._localHold || this._remoteHold) {
              enableAudio = false;
              enableVideo = false;
            }
            if (this._audioMuted) {
              enableAudio = false;
            }
            if (this._videoMuted) {
              enableVideo = false;
            }
            this._toggleMuteAudio(!enableAudio);
            this._toggleMuteVideo(!enableVideo);
          }
          /**
           * Handle SessionTimers for an incoming INVITE or UPDATE.
           * @param  {IncomingRequest} request
           * @param  {Array} responseExtraHeaders  Extra headers for the 200 response.
           */
        }, {
          key: "_handleSessionTimersInIncomingRequest",
          value: function _handleSessionTimersInIncomingRequest(request, responseExtraHeaders) {
            if (!this._sessionTimers.enabled) {
              return;
            }
            var session_expires_refresher;
            if (request.session_expires && request.session_expires >= JsSIP_C.MIN_SESSION_EXPIRES) {
              this._sessionTimers.currentExpires = request.session_expires;
              session_expires_refresher = request.session_expires_refresher || "uas";
            } else {
              this._sessionTimers.currentExpires = this._sessionTimers.defaultExpires;
              session_expires_refresher = "uas";
            }
            responseExtraHeaders.push("Session-Expires: ".concat(this._sessionTimers.currentExpires, ";refresher=").concat(session_expires_refresher));
            this._sessionTimers.refresher = session_expires_refresher === "uas";
            this._runSessionTimer();
          }
          /**
           * Handle SessionTimers for an incoming response to INVITE or UPDATE.
           * @param  {IncomingResponse} response
           */
        }, {
          key: "_handleSessionTimersInIncomingResponse",
          value: function _handleSessionTimersInIncomingResponse(response) {
            if (!this._sessionTimers.enabled) {
              return;
            }
            var session_expires_refresher;
            if (response.session_expires && response.session_expires >= JsSIP_C.MIN_SESSION_EXPIRES) {
              this._sessionTimers.currentExpires = response.session_expires;
              session_expires_refresher = response.session_expires_refresher || "uac";
            } else {
              this._sessionTimers.currentExpires = this._sessionTimers.defaultExpires;
              session_expires_refresher = "uac";
            }
            this._sessionTimers.refresher = session_expires_refresher === "uac";
            this._runSessionTimer();
          }
        }, {
          key: "_runSessionTimer",
          value: function _runSessionTimer() {
            var _this27 = this;
            var expires = this._sessionTimers.currentExpires;
            this._sessionTimers.running = true;
            clearTimeout(this._sessionTimers.timer);
            if (this._sessionTimers.refresher) {
              this._sessionTimers.timer = setTimeout(function() {
                if (_this27._status === C.STATUS_TERMINATED) {
                  return;
                }
                if (!_this27._isReadyToReOffer()) {
                  return;
                }
                logger.debug("runSessionTimer() | sending session refresh request");
                if (_this27._sessionTimers.refreshMethod === JsSIP_C.UPDATE) {
                  _this27._sendUpdate();
                } else {
                  _this27._sendReinvite();
                }
              }, expires * 500);
            } else {
              this._sessionTimers.timer = setTimeout(function() {
                if (_this27._status === C.STATUS_TERMINATED) {
                  return;
                }
                logger.warn("runSessionTimer() | timer expired, terminating the session");
                _this27.terminate({
                  cause: JsSIP_C.causes.REQUEST_TIMEOUT,
                  status_code: 408,
                  reason_phrase: "Session Timer Expired"
                });
              }, expires * 1100);
            }
          }
        }, {
          key: "_toggleMuteAudio",
          value: function _toggleMuteAudio(mute) {
            var senders = this._connection.getSenders().filter(function(sender2) {
              return sender2.track && sender2.track.kind === "audio";
            });
            var _iterator8 = _createForOfIteratorHelper(senders), _step8;
            try {
              for (_iterator8.s(); !(_step8 = _iterator8.n()).done; ) {
                var sender = _step8.value;
                sender.track.enabled = !mute;
              }
            } catch (err) {
              _iterator8.e(err);
            } finally {
              _iterator8.f();
            }
          }
        }, {
          key: "_toggleMuteVideo",
          value: function _toggleMuteVideo(mute) {
            var senders = this._connection.getSenders().filter(function(sender2) {
              return sender2.track && sender2.track.kind === "video";
            });
            var _iterator9 = _createForOfIteratorHelper(senders), _step9;
            try {
              for (_iterator9.s(); !(_step9 = _iterator9.n()).done; ) {
                var sender = _step9.value;
                sender.track.enabled = !mute;
              }
            } catch (err) {
              _iterator9.e(err);
            } finally {
              _iterator9.f();
            }
          }
        }, {
          key: "_newRTCSession",
          value: function _newRTCSession(originator, request) {
            logger.debug("newRTCSession()");
            this._ua.newRTCSession(this, {
              originator,
              session: this,
              request
            });
          }
        }, {
          key: "_connecting",
          value: function _connecting(request) {
            logger.debug("session connecting");
            logger.debug('emit "connecting"');
            this.emit("connecting", {
              request
            });
          }
        }, {
          key: "_progress",
          value: function _progress(originator, response) {
            logger.debug("session progress");
            logger.debug('emit "progress"');
            this.emit("progress", {
              originator,
              response: response || null
            });
          }
        }, {
          key: "_accepted",
          value: function _accepted(originator, message) {
            logger.debug("session accepted");
            this._start_time = /* @__PURE__ */ new Date();
            logger.debug('emit "accepted"');
            this.emit("accepted", {
              originator,
              response: message || null
            });
          }
        }, {
          key: "_confirmed",
          value: function _confirmed(originator, ack) {
            logger.debug("session confirmed");
            this._is_confirmed = true;
            logger.debug('emit "confirmed"');
            this.emit("confirmed", {
              originator,
              ack: ack || null
            });
          }
        }, {
          key: "_ended",
          value: function _ended(originator, message, cause) {
            logger.debug("session ended");
            this._end_time = /* @__PURE__ */ new Date();
            this._close();
            logger.debug('emit "ended"');
            this.emit("ended", {
              originator,
              message: message || null,
              cause
            });
          }
        }, {
          key: "_failed",
          value: function _failed(originator, message, cause) {
            logger.debug("session failed");
            logger.debug('emit "_failed"');
            this.emit("_failed", {
              originator,
              message: message || null,
              cause
            });
            this._close();
            logger.debug('emit "failed"');
            this.emit("failed", {
              originator,
              message: message || null,
              cause
            });
          }
        }, {
          key: "_onhold",
          value: function _onhold(originator) {
            logger.debug("session onhold");
            this._setLocalMediaStatus();
            logger.debug('emit "hold"');
            this.emit("hold", {
              originator
            });
          }
        }, {
          key: "_onunhold",
          value: function _onunhold(originator) {
            logger.debug("session onunhold");
            this._setLocalMediaStatus();
            logger.debug('emit "unhold"');
            this.emit("unhold", {
              originator
            });
          }
        }, {
          key: "_onmute",
          value: function _onmute(_ref5) {
            var audio = _ref5.audio, video = _ref5.video;
            logger.debug("session onmute");
            this._setLocalMediaStatus();
            logger.debug('emit "muted"');
            this.emit("muted", {
              audio,
              video
            });
          }
        }, {
          key: "_onunmute",
          value: function _onunmute(_ref6) {
            var audio = _ref6.audio, video = _ref6.video;
            logger.debug("session onunmute");
            this._setLocalMediaStatus();
            logger.debug('emit "unmuted"');
            this.emit("unmuted", {
              audio,
              video
            });
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
          // Expose session failed/ended causes as a property of the RTCSession instance.
        }, {
          key: "causes",
          get: function get() {
            return JsSIP_C.causes;
          }
        }, {
          key: "id",
          get: function get() {
            return this._id;
          }
        }, {
          key: "connection",
          get: function get() {
            return this._connection;
          }
        }, {
          key: "contact",
          get: function get() {
            return this._contact;
          }
        }, {
          key: "direction",
          get: function get() {
            return this._direction;
          }
        }, {
          key: "local_identity",
          get: function get() {
            return this._local_identity;
          }
        }, {
          key: "remote_identity",
          get: function get() {
            return this._remote_identity;
          }
        }, {
          key: "start_time",
          get: function get() {
            return this._start_time;
          }
        }, {
          key: "end_time",
          get: function get() {
            return this._end_time;
          }
        }, {
          key: "data",
          get: function get() {
            return this._data;
          },
          set: function set(_data) {
            this._data = _data;
          }
        }, {
          key: "status",
          get: function get() {
            return this._status;
          }
        }]);
        return RTCSession;
      }(EventEmitter);
    }
  });

  // node_modules/jssip/lib-es5/Message.js
  var require_Message = __commonJS({
    "node_modules/jssip/lib-es5/Message.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var SIPMessage = require_SIPMessage();
      var Utils = require_Utils();
      var RequestSender = require_RequestSender();
      var Exceptions = require_Exceptions();
      var URI = require_URI();
      var logger = new Logger("Message");
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(Message, _EventEmitter);
        var _super = _createSuper(Message);
        function Message(ua) {
          var _this;
          _classCallCheck(this, Message);
          _this = _super.call(this);
          _this._ua = ua;
          _this._request = null;
          _this._closed = false;
          _this._direction = null;
          _this._local_identity = null;
          _this._remote_identity = null;
          _this._is_replied = false;
          _this._data = {};
          return _this;
        }
        _createClass(Message, [{
          key: "send",
          value: function send(target, body) {
            var _this2 = this;
            var options = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : {};
            var originalTarget = target;
            if (target === void 0 || body === void 0) {
              throw new TypeError("Not enough arguments");
            }
            target = this._ua.normalizeTarget(target);
            if (!target) {
              throw new TypeError("Invalid target: ".concat(originalTarget));
            }
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var contentType = options.contentType || "text/plain";
            var requestParams = {};
            if (options.fromUserName) {
              requestParams.from_uri = new URI("sip", options.fromUserName, this._ua.configuration.uri.host);
              extraHeaders.push("P-Preferred-Identity: ".concat(this._ua.configuration.uri.toString()));
            }
            if (options.fromDisplayName) {
              requestParams.from_display_name = options.fromDisplayName;
            }
            for (var event in eventHandlers) {
              if (Object.prototype.hasOwnProperty.call(eventHandlers, event)) {
                this.on(event, eventHandlers[event]);
              }
            }
            extraHeaders.push("Content-Type: ".concat(contentType));
            this._request = new SIPMessage.OutgoingRequest(JsSIP_C.MESSAGE, target, this._ua, requestParams, extraHeaders);
            if (body) {
              this._request.body = body;
            }
            var request_sender = new RequestSender(this._ua, this._request, {
              onRequestTimeout: function onRequestTimeout() {
                _this2._onRequestTimeout();
              },
              onTransportError: function onTransportError() {
                _this2._onTransportError();
              },
              onReceiveResponse: function onReceiveResponse(response) {
                _this2._receiveResponse(response);
              }
            });
            this._newMessage("local", this._request);
            request_sender.send();
          }
        }, {
          key: "init_incoming",
          value: function init_incoming(request) {
            this._request = request;
            this._newMessage("remote", request);
            if (!this._is_replied) {
              this._is_replied = true;
              request.reply(200);
            }
            this._close();
          }
          /**
           * Accept the incoming Message
           * Only valid for incoming Messages
           */
        }, {
          key: "accept",
          value: function accept() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var body = options.body;
            if (this._direction !== "incoming") {
              throw new Exceptions.NotSupportedError('"accept" not supported for outgoing Message');
            }
            if (this._is_replied) {
              throw new Error("incoming Message already replied");
            }
            this._is_replied = true;
            this._request.reply(200, null, extraHeaders, body);
          }
          /**
           * Reject the incoming Message
           * Only valid for incoming Messages
           */
        }, {
          key: "reject",
          value: function reject() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var status_code = options.status_code || 480;
            var reason_phrase = options.reason_phrase;
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var body = options.body;
            if (this._direction !== "incoming") {
              throw new Exceptions.NotSupportedError('"reject" not supported for outgoing Message');
            }
            if (this._is_replied) {
              throw new Error("incoming Message already replied");
            }
            if (status_code < 300 || status_code >= 700) {
              throw new TypeError("Invalid status_code: ".concat(status_code));
            }
            this._is_replied = true;
            this._request.reply(status_code, reason_phrase, extraHeaders, body);
          }
        }, {
          key: "_receiveResponse",
          value: function _receiveResponse(response) {
            if (this._closed) {
              return;
            }
            switch (true) {
              case /^1[0-9]{2}$/.test(response.status_code):
                break;
              case /^2[0-9]{2}$/.test(response.status_code):
                this._succeeded("remote", response);
                break;
              default: {
                var cause = Utils.sipErrorCause(response.status_code);
                this._failed("remote", response, cause);
                break;
              }
            }
          }
        }, {
          key: "_onRequestTimeout",
          value: function _onRequestTimeout() {
            if (this._closed) {
              return;
            }
            this._failed("system", null, JsSIP_C.causes.REQUEST_TIMEOUT);
          }
        }, {
          key: "_onTransportError",
          value: function _onTransportError() {
            if (this._closed) {
              return;
            }
            this._failed("system", null, JsSIP_C.causes.CONNECTION_ERROR);
          }
        }, {
          key: "_close",
          value: function _close() {
            this._closed = true;
            this._ua.destroyMessage(this);
          }
          /**
           * Internal Callbacks
           */
        }, {
          key: "_newMessage",
          value: function _newMessage(originator, request) {
            if (originator === "remote") {
              this._direction = "incoming";
              this._local_identity = request.to;
              this._remote_identity = request.from;
            } else if (originator === "local") {
              this._direction = "outgoing";
              this._local_identity = request.from;
              this._remote_identity = request.to;
            }
            this._ua.newMessage(this, {
              originator,
              message: this,
              request
            });
          }
        }, {
          key: "_failed",
          value: function _failed(originator, response, cause) {
            logger.debug("MESSAGE failed");
            this._close();
            logger.debug('emit "failed"');
            this.emit("failed", {
              originator,
              response: response || null,
              cause
            });
          }
        }, {
          key: "_succeeded",
          value: function _succeeded(originator, response) {
            logger.debug("MESSAGE succeeded");
            this._close();
            logger.debug('emit "succeeded"');
            this.emit("succeeded", {
              originator,
              response
            });
          }
        }, {
          key: "direction",
          get: function get() {
            return this._direction;
          }
        }, {
          key: "local_identity",
          get: function get() {
            return this._local_identity;
          }
        }, {
          key: "remote_identity",
          get: function get() {
            return this._remote_identity;
          }
        }]);
        return Message;
      }(EventEmitter);
    }
  });

  // node_modules/jssip/lib-es5/Options.js
  var require_Options = __commonJS({
    "node_modules/jssip/lib-es5/Options.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var SIPMessage = require_SIPMessage();
      var Utils = require_Utils();
      var RequestSender = require_RequestSender();
      var Exceptions = require_Exceptions();
      var logger = new Logger("Options");
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(Options, _EventEmitter);
        var _super = _createSuper(Options);
        function Options(ua) {
          var _this;
          _classCallCheck(this, Options);
          _this = _super.call(this);
          _this._ua = ua;
          _this._request = null;
          _this._closed = false;
          _this._direction = null;
          _this._local_identity = null;
          _this._remote_identity = null;
          _this._is_replied = false;
          _this._data = {};
          return _this;
        }
        _createClass(Options, [{
          key: "send",
          value: function send(target, body) {
            var _this2 = this;
            var options = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : {};
            var originalTarget = target;
            if (target === void 0) {
              throw new TypeError("A target is required for OPTIONS");
            }
            target = this._ua.normalizeTarget(target);
            if (!target) {
              throw new TypeError("Invalid target: ".concat(originalTarget));
            }
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var eventHandlers = Utils.cloneObject(options.eventHandlers);
            var contentType = options.contentType || "application/sdp";
            for (var event in eventHandlers) {
              if (Object.prototype.hasOwnProperty.call(eventHandlers, event)) {
                this.on(event, eventHandlers[event]);
              }
            }
            extraHeaders.push("Content-Type: ".concat(contentType));
            this._request = new SIPMessage.OutgoingRequest(JsSIP_C.OPTIONS, target, this._ua, null, extraHeaders);
            if (body) {
              this._request.body = body;
            }
            var request_sender = new RequestSender(this._ua, this._request, {
              onRequestTimeout: function onRequestTimeout() {
                _this2._onRequestTimeout();
              },
              onTransportError: function onTransportError() {
                _this2._onTransportError();
              },
              onReceiveResponse: function onReceiveResponse(response) {
                _this2._receiveResponse(response);
              }
            });
            this._newOptions("local", this._request);
            request_sender.send();
          }
        }, {
          key: "init_incoming",
          value: function init_incoming(request) {
            this._request = request;
            this._newOptions("remote", request);
            if (!this._is_replied) {
              this._is_replied = true;
              request.reply(200);
            }
            this._close();
          }
          /**
           * Accept the incoming Options
           * Only valid for incoming Options
           */
        }, {
          key: "accept",
          value: function accept() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var body = options.body;
            if (this._direction !== "incoming") {
              throw new Exceptions.NotSupportedError('"accept" not supported for outgoing Options');
            }
            if (this._is_replied) {
              throw new Error("incoming Options already replied");
            }
            this._is_replied = true;
            this._request.reply(200, null, extraHeaders, body);
          }
          /**
           * Reject the incoming Options
           * Only valid for incoming Options
           */
        }, {
          key: "reject",
          value: function reject() {
            var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
            var status_code = options.status_code || 480;
            var reason_phrase = options.reason_phrase;
            var extraHeaders = Utils.cloneArray(options.extraHeaders);
            var body = options.body;
            if (this._direction !== "incoming") {
              throw new Exceptions.NotSupportedError('"reject" not supported for outgoing Options');
            }
            if (this._is_replied) {
              throw new Error("incoming Options already replied");
            }
            if (status_code < 300 || status_code >= 700) {
              throw new TypeError("Invalid status_code: ".concat(status_code));
            }
            this._is_replied = true;
            this._request.reply(status_code, reason_phrase, extraHeaders, body);
          }
        }, {
          key: "_receiveResponse",
          value: function _receiveResponse(response) {
            if (this._closed) {
              return;
            }
            switch (true) {
              case /^1[0-9]{2}$/.test(response.status_code):
                break;
              case /^2[0-9]{2}$/.test(response.status_code):
                this._succeeded("remote", response);
                break;
              default: {
                var cause = Utils.sipErrorCause(response.status_code);
                this._failed("remote", response, cause);
                break;
              }
            }
          }
        }, {
          key: "_onRequestTimeout",
          value: function _onRequestTimeout() {
            if (this._closed) {
              return;
            }
            this._failed("system", null, JsSIP_C.causes.REQUEST_TIMEOUT);
          }
        }, {
          key: "_onTransportError",
          value: function _onTransportError() {
            if (this._closed) {
              return;
            }
            this._failed("system", null, JsSIP_C.causes.CONNECTION_ERROR);
          }
        }, {
          key: "_close",
          value: function _close() {
            this._closed = true;
            this._ua.destroyMessage(this);
          }
          /**
           * Internal Callbacks
           */
        }, {
          key: "_newOptions",
          value: function _newOptions(originator, request) {
            if (originator === "remote") {
              this._direction = "incoming";
              this._local_identity = request.to;
              this._remote_identity = request.from;
            } else if (originator === "local") {
              this._direction = "outgoing";
              this._local_identity = request.from;
              this._remote_identity = request.to;
            }
            this._ua.newOptions(this, {
              originator,
              message: this,
              request
            });
          }
        }, {
          key: "_failed",
          value: function _failed(originator, response, cause) {
            logger.debug("OPTIONS failed");
            this._close();
            logger.debug('emit "failed"');
            this.emit("failed", {
              originator,
              response: response || null,
              cause
            });
          }
        }, {
          key: "_succeeded",
          value: function _succeeded(originator, response) {
            logger.debug("OPTIONS succeeded");
            this._close();
            logger.debug('emit "succeeded"');
            this.emit("succeeded", {
              originator,
              response
            });
          }
        }, {
          key: "direction",
          get: function get() {
            return this._direction;
          }
        }, {
          key: "local_identity",
          get: function get() {
            return this._local_identity;
          }
        }, {
          key: "remote_identity",
          get: function get() {
            return this._remote_identity;
          }
        }]);
        return Options;
      }(EventEmitter);
    }
  });

  // node_modules/jssip/lib-es5/Socket.js
  var require_Socket = __commonJS({
    "node_modules/jssip/lib-es5/Socket.js"(exports) {
      "use strict";
      var Logger = require_Logger();
      var Utils = require_Utils();
      var Grammar = require_Grammar();
      var logger = new Logger("Socket");
      exports.isSocket = function(socket) {
        if (Array.isArray(socket)) {
          return false;
        }
        if (typeof socket === "undefined") {
          logger.warn("undefined JsSIP.Socket instance");
          return false;
        }
        try {
          if (!Utils.isString(socket.url)) {
            logger.warn("missing or invalid JsSIP.Socket url property");
            throw new Error("Missing or invalid JsSIP.Socket url property");
          }
          if (!Utils.isString(socket.via_transport)) {
            logger.warn("missing or invalid JsSIP.Socket via_transport property");
            throw new Error("Missing or invalid JsSIP.Socket via_transport property");
          }
          if (Grammar.parse(socket.sip_uri, "SIP_URI") === -1) {
            logger.warn("missing or invalid JsSIP.Socket sip_uri property");
            throw new Error("missing or invalid JsSIP.Socket sip_uri property");
          }
        } catch (e) {
          return false;
        }
        try {
          ["connect", "disconnect", "send"].forEach(function(method) {
            if (!Utils.isFunction(socket[method])) {
              logger.warn("missing or invalid JsSIP.Socket method: ".concat(method));
              throw new Error("Missing or invalid JsSIP.Socket method: ".concat(method));
            }
          });
        } catch (e) {
          return false;
        }
        return true;
      };
    }
  });

  // node_modules/jssip/lib-es5/Transport.js
  var require_Transport = __commonJS({
    "node_modules/jssip/lib-es5/Transport.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var Socket = require_Socket();
      var JsSIP_C = require_Constants();
      var logger = new Logger("Transport");
      var C = {
        // Transport status.
        STATUS_CONNECTED: 0,
        STATUS_CONNECTING: 1,
        STATUS_DISCONNECTED: 2,
        // Socket status.
        SOCKET_STATUS_READY: 0,
        SOCKET_STATUS_ERROR: 1,
        // Recovery options.
        recovery_options: {
          // minimum interval in seconds between recover attempts.
          min_interval: JsSIP_C.CONNECTION_RECOVERY_MIN_INTERVAL,
          // maximum interval in seconds between recover attempts.
          max_interval: JsSIP_C.CONNECTION_RECOVERY_MAX_INTERVAL
        }
      };
      module.exports = /* @__PURE__ */ function() {
        function Transport(sockets) {
          var recovery_options = arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : C.recovery_options;
          _classCallCheck(this, Transport);
          logger.debug("new()");
          this.status = C.STATUS_DISCONNECTED;
          this.socket = null;
          this.sockets = [];
          this.recovery_options = recovery_options;
          this.recover_attempts = 0;
          this.recovery_timer = null;
          this.close_requested = false;
          try {
            this.textDecoder = new TextDecoder("utf8");
          } catch (error) {
            logger.warn("cannot use TextDecoder: ".concat(error));
          }
          if (typeof sockets === "undefined") {
            throw new TypeError("Invalid argument. undefined 'sockets' argument");
          }
          if (!(sockets instanceof Array)) {
            sockets = [sockets];
          }
          sockets.forEach(function(socket) {
            if (!Socket.isSocket(socket.socket)) {
              throw new TypeError("Invalid argument. invalid 'JsSIP.Socket' instance");
            }
            if (socket.weight && !Number(socket.weight)) {
              throw new TypeError("Invalid argument. 'weight' attribute is not a number");
            }
            this.sockets.push({
              socket: socket.socket,
              weight: socket.weight || 0,
              status: C.SOCKET_STATUS_READY
            });
          }, this);
          this._getSocket();
        }
        _createClass(Transport, [{
          key: "connect",
          value: function connect() {
            logger.debug("connect()");
            if (this.isConnected()) {
              logger.debug("Transport is already connected");
              return;
            } else if (this.isConnecting()) {
              logger.debug("Transport is connecting");
              return;
            }
            this.close_requested = false;
            this.status = C.STATUS_CONNECTING;
            this.onconnecting({
              socket: this.socket,
              attempts: this.recover_attempts
            });
            if (!this.close_requested) {
              this.socket.onconnect = this._onConnect.bind(this);
              this.socket.ondisconnect = this._onDisconnect.bind(this);
              this.socket.ondata = this._onData.bind(this);
              this.socket.connect();
            }
            return;
          }
        }, {
          key: "disconnect",
          value: function disconnect() {
            logger.debug("close()");
            this.close_requested = true;
            this.recover_attempts = 0;
            this.status = C.STATUS_DISCONNECTED;
            if (this.recovery_timer !== null) {
              clearTimeout(this.recovery_timer);
              this.recovery_timer = null;
            }
            this.socket.onconnect = function() {
            };
            this.socket.ondisconnect = function() {
            };
            this.socket.ondata = function() {
            };
            this.socket.disconnect();
            this.ondisconnect({
              socket: this.socket,
              error: false
            });
          }
        }, {
          key: "send",
          value: function send(data) {
            logger.debug("send()");
            if (!this.isConnected()) {
              logger.warn("unable to send message, transport is not connected");
              return false;
            }
            var message = data.toString();
            logger.debug("sending message:\n\n".concat(message, "\n"));
            return this.socket.send(message);
          }
        }, {
          key: "isConnected",
          value: function isConnected() {
            return this.status === C.STATUS_CONNECTED;
          }
        }, {
          key: "isConnecting",
          value: function isConnecting() {
            return this.status === C.STATUS_CONNECTING;
          }
          /**
           * Private API.
           */
        }, {
          key: "_reconnect",
          value: function _reconnect() {
            var _this = this;
            this.recover_attempts += 1;
            var k = Math.floor(Math.random() * Math.pow(2, this.recover_attempts) + 1);
            if (k < this.recovery_options.min_interval) {
              k = this.recovery_options.min_interval;
            } else if (k > this.recovery_options.max_interval) {
              k = this.recovery_options.max_interval;
            }
            logger.debug("reconnection attempt: ".concat(this.recover_attempts, ". next connection attempt in ").concat(k, " seconds"));
            this.recovery_timer = setTimeout(function() {
              if (!_this.close_requested && !(_this.isConnected() || _this.isConnecting())) {
                _this._getSocket();
                _this.connect();
              }
            }, k * 1e3);
          }
          /**
           * get the next available socket with higher weight
           */
        }, {
          key: "_getSocket",
          value: function _getSocket() {
            var candidates = [];
            this.sockets.forEach(function(socket) {
              if (socket.status === C.SOCKET_STATUS_ERROR) {
                return;
              } else if (candidates.length === 0) {
                candidates.push(socket);
              } else if (socket.weight > candidates[0].weight) {
                candidates = [socket];
              } else if (socket.weight === candidates[0].weight) {
                candidates.push(socket);
              }
            });
            if (candidates.length === 0) {
              this.sockets.forEach(function(socket) {
                socket.status = C.SOCKET_STATUS_READY;
              });
              this._getSocket();
              return;
            }
            var idx = Math.floor(Math.random() * candidates.length);
            this.socket = candidates[idx].socket;
          }
          /**
           * Socket Event Handlers
           */
        }, {
          key: "_onConnect",
          value: function _onConnect() {
            this.recover_attempts = 0;
            this.status = C.STATUS_CONNECTED;
            if (this.recovery_timer !== null) {
              clearTimeout(this.recovery_timer);
              this.recovery_timer = null;
            }
            this.onconnect({
              socket: this
            });
          }
        }, {
          key: "_onDisconnect",
          value: function _onDisconnect(error, code, reason) {
            this.status = C.STATUS_DISCONNECTED;
            this.ondisconnect({
              socket: this.socket,
              error,
              code,
              reason
            });
            if (this.close_requested) {
              return;
            } else {
              this.sockets.forEach(function(socket) {
                if (this.socket === socket.socket) {
                  socket.status = C.SOCKET_STATUS_ERROR;
                }
              }, this);
            }
            this._reconnect(error);
          }
        }, {
          key: "_onData",
          value: function _onData(data) {
            if (data === "\r\n\r\n") {
              logger.debug("received message with double-CRLF Keep Alive request");
              try {
                this.socket.send("\r\n");
              } catch (error) {
                logger.warn("error sending Keep Alive response: ".concat(error));
              }
              return;
            }
            if (data === "\r\n") {
              logger.debug("received message with CRLF Keep Alive response");
              return;
            } else if (typeof data !== "string") {
              try {
                if (this.textDecoder) data = this.textDecoder.decode(data);
                else data = String.fromCharCode.apply(null, new Uint8Array(data));
              } catch (evt) {
                logger.debug("received binary message failed to be converted into string, message discarded");
                return;
              }
              logger.debug("received binary message:\n\n".concat(data, "\n"));
            } else {
              logger.debug("received text message:\n\n".concat(data, "\n"));
            }
            this.ondata({
              transport: this,
              message: data
            });
          }
        }, {
          key: "via_transport",
          get: function get() {
            return this.socket.via_transport;
          }
        }, {
          key: "url",
          get: function get() {
            return this.socket.url;
          }
        }, {
          key: "sip_uri",
          get: function get() {
            return this.socket.sip_uri;
          }
        }]);
        return Transport;
      }();
    }
  });

  // node_modules/jssip/lib-es5/Parser.js
  var require_Parser = __commonJS({
    "node_modules/jssip/lib-es5/Parser.js"(exports) {
      "use strict";
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      var Logger = require_Logger();
      var Grammar = require_Grammar();
      var SIPMessage = require_SIPMessage();
      var logger = new Logger("Parser");
      exports.parseMessage = function(data, ua) {
        var message;
        var bodyStart;
        var headerEnd = data.indexOf("\r\n");
        if (headerEnd === -1) {
          logger.warn("parseMessage() | no CRLF found, not a SIP message");
          return;
        }
        var firstLine = data.substring(0, headerEnd);
        var parsed = Grammar.parse(firstLine, "Request_Response");
        if (parsed === -1) {
          logger.warn('parseMessage() | error parsing first line of SIP message: "'.concat(firstLine, '"'));
          return;
        } else if (!parsed.status_code) {
          message = new SIPMessage.IncomingRequest(ua);
          message.method = parsed.method;
          message.ruri = parsed.uri;
        } else {
          message = new SIPMessage.IncomingResponse();
          message.status_code = parsed.status_code;
          message.reason_phrase = parsed.reason_phrase;
        }
        message.data = data;
        var headerStart = headerEnd + 2;
        while (true) {
          headerEnd = getHeader(data, headerStart);
          if (headerEnd === -2) {
            bodyStart = headerStart + 2;
            break;
          } else if (headerEnd === -1) {
            logger.warn("parseMessage() | malformed message");
            return;
          }
          parsed = parseHeader(message, data, headerStart, headerEnd);
          if (parsed !== true) {
            logger.warn("parseMessage() |", parsed.error);
            return;
          }
          headerStart = headerEnd + 2;
        }
        if (message.hasHeader("content-length")) {
          var contentLength = message.getHeader("content-length");
          message.body = data.substr(bodyStart, contentLength);
        } else {
          message.body = data.substring(bodyStart);
        }
        return message;
      };
      function getHeader(data, headerStart) {
        var start = headerStart;
        var end = 0;
        var partialEnd = 0;
        if (data.substring(start, start + 2).match(/(^\r\n)/)) {
          return -2;
        }
        while (end === 0) {
          partialEnd = data.indexOf("\r\n", start);
          if (partialEnd === -1) {
            return partialEnd;
          }
          if (!data.substring(partialEnd + 2, partialEnd + 4).match(/(^\r\n)/) && data.charAt(partialEnd + 2).match(/(^\s+)/)) {
            start = partialEnd + 2;
          } else {
            end = partialEnd;
          }
        }
        return end;
      }
      function parseHeader(message, data, headerStart, headerEnd) {
        var parsed;
        var hcolonIndex = data.indexOf(":", headerStart);
        var headerName = data.substring(headerStart, hcolonIndex).trim();
        var headerValue = data.substring(hcolonIndex + 1, headerEnd).trim();
        switch (headerName.toLowerCase()) {
          case "via":
          case "v":
            message.addHeader("via", headerValue);
            if (message.getHeaders("via").length === 1) {
              parsed = message.parseHeader("Via");
              if (parsed) {
                message.via = parsed;
                message.via_branch = parsed.branch;
              }
            } else {
              parsed = 0;
            }
            break;
          case "from":
          case "f":
            message.setHeader("from", headerValue);
            parsed = message.parseHeader("from");
            if (parsed) {
              message.from = parsed;
              message.from_tag = parsed.getParam("tag");
            }
            break;
          case "to":
          case "t":
            message.setHeader("to", headerValue);
            parsed = message.parseHeader("to");
            if (parsed) {
              message.to = parsed;
              message.to_tag = parsed.getParam("tag");
            }
            break;
          case "record-route":
            parsed = Grammar.parse(headerValue, "Record_Route");
            if (parsed === -1) {
              parsed = void 0;
            } else {
              var _iterator = _createForOfIteratorHelper(parsed), _step;
              try {
                for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                  var header = _step.value;
                  message.addHeader("record-route", headerValue.substring(header.possition, header.offset));
                  message.headers["Record-Route"][message.getHeaders("record-route").length - 1].parsed = header.parsed;
                }
              } catch (err) {
                _iterator.e(err);
              } finally {
                _iterator.f();
              }
            }
            break;
          case "call-id":
          case "i":
            message.setHeader("call-id", headerValue);
            parsed = message.parseHeader("call-id");
            if (parsed) {
              message.call_id = headerValue;
            }
            break;
          case "contact":
          case "m":
            parsed = Grammar.parse(headerValue, "Contact");
            if (parsed === -1) {
              parsed = void 0;
            } else {
              var _iterator2 = _createForOfIteratorHelper(parsed), _step2;
              try {
                for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
                  var _header = _step2.value;
                  message.addHeader("contact", headerValue.substring(_header.possition, _header.offset));
                  message.headers.Contact[message.getHeaders("contact").length - 1].parsed = _header.parsed;
                }
              } catch (err) {
                _iterator2.e(err);
              } finally {
                _iterator2.f();
              }
            }
            break;
          case "content-length":
          case "l":
            message.setHeader("content-length", headerValue);
            parsed = message.parseHeader("content-length");
            break;
          case "content-type":
          case "c":
            message.setHeader("content-type", headerValue);
            parsed = message.parseHeader("content-type");
            break;
          case "cseq":
            message.setHeader("cseq", headerValue);
            parsed = message.parseHeader("cseq");
            if (parsed) {
              message.cseq = parsed.value;
            }
            if (message instanceof SIPMessage.IncomingResponse) {
              message.method = parsed.method;
            }
            break;
          case "max-forwards":
            message.setHeader("max-forwards", headerValue);
            parsed = message.parseHeader("max-forwards");
            break;
          case "www-authenticate":
            message.setHeader("www-authenticate", headerValue);
            parsed = message.parseHeader("www-authenticate");
            break;
          case "proxy-authenticate":
            message.setHeader("proxy-authenticate", headerValue);
            parsed = message.parseHeader("proxy-authenticate");
            break;
          case "session-expires":
          case "x":
            message.setHeader("session-expires", headerValue);
            parsed = message.parseHeader("session-expires");
            if (parsed) {
              message.session_expires = parsed.expires;
              message.session_expires_refresher = parsed.refresher;
            }
            break;
          case "refer-to":
          case "r":
            message.setHeader("refer-to", headerValue);
            parsed = message.parseHeader("refer-to");
            if (parsed) {
              message.refer_to = parsed;
            }
            break;
          case "replaces":
            message.setHeader("replaces", headerValue);
            parsed = message.parseHeader("replaces");
            if (parsed) {
              message.replaces = parsed;
            }
            break;
          case "event":
          case "o":
            message.setHeader("event", headerValue);
            parsed = message.parseHeader("event");
            if (parsed) {
              message.event = parsed;
            }
            break;
          default:
            message.addHeader(headerName, headerValue);
            parsed = 0;
        }
        if (parsed === void 0) {
          return {
            error: 'error parsing header "'.concat(headerName, '"')
          };
        } else {
          return true;
        }
      }
    }
  });

  // node_modules/jssip/lib-es5/sanityCheck.js
  var require_sanityCheck = __commonJS({
    "node_modules/jssip/lib-es5/sanityCheck.js"(exports, module) {
      "use strict";
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var SIPMessage = require_SIPMessage();
      var Utils = require_Utils();
      var logger = new Logger("sanityCheck");
      var all = [minimumHeaders];
      var requests = [rfc3261_8_2_2_1, rfc3261_16_3_4, rfc3261_18_3_request, rfc3261_8_2_2_2];
      var responses = [rfc3261_8_1_3_3, rfc3261_18_3_response];
      var message;
      var ua;
      var transport;
      module.exports = function(m, u, t) {
        message = m;
        ua = u;
        transport = t;
        var _iterator = _createForOfIteratorHelper(all), _step;
        try {
          for (_iterator.s(); !(_step = _iterator.n()).done; ) {
            var _check2 = _step.value;
            if (_check2() === false) {
              return false;
            }
          }
        } catch (err) {
          _iterator.e(err);
        } finally {
          _iterator.f();
        }
        if (message instanceof SIPMessage.IncomingRequest) {
          var _iterator2 = _createForOfIteratorHelper(requests), _step2;
          try {
            for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
              var check = _step2.value;
              if (check() === false) {
                return false;
              }
            }
          } catch (err) {
            _iterator2.e(err);
          } finally {
            _iterator2.f();
          }
        } else if (message instanceof SIPMessage.IncomingResponse) {
          var _iterator3 = _createForOfIteratorHelper(responses), _step3;
          try {
            for (_iterator3.s(); !(_step3 = _iterator3.n()).done; ) {
              var _check = _step3.value;
              if (_check() === false) {
                return false;
              }
            }
          } catch (err) {
            _iterator3.e(err);
          } finally {
            _iterator3.f();
          }
        }
        return true;
      };
      function rfc3261_8_2_2_1() {
        if (message.s("to").uri.scheme !== "sip") {
          reply(416);
          return false;
        }
      }
      function rfc3261_16_3_4() {
        if (!message.to_tag) {
          if (message.call_id.substr(0, 5) === ua.configuration.jssip_id) {
            reply(482);
            return false;
          }
        }
      }
      function rfc3261_18_3_request() {
        var len = Utils.str_utf8_length(message.body);
        var contentLength = message.getHeader("content-length");
        if (len < contentLength) {
          reply(400);
          return false;
        }
      }
      function rfc3261_8_2_2_2() {
        var fromTag = message.from_tag;
        var call_id = message.call_id;
        var cseq = message.cseq;
        var tr;
        if (message.to_tag) {
          return;
        }
        if (message.method === JsSIP_C.INVITE) {
          if (ua._transactions.ist[message.via_branch]) {
            return false;
          } else {
            for (var transaction in ua._transactions.ist) {
              if (Object.prototype.hasOwnProperty.call(ua._transactions.ist, transaction)) {
                tr = ua._transactions.ist[transaction];
                if (tr.request.from_tag === fromTag && tr.request.call_id === call_id && tr.request.cseq === cseq) {
                  reply(482);
                  return false;
                }
              }
            }
          }
        } else if (ua._transactions.nist[message.via_branch]) {
          return false;
        } else {
          for (var _transaction in ua._transactions.nist) {
            if (Object.prototype.hasOwnProperty.call(ua._transactions.nist, _transaction)) {
              tr = ua._transactions.nist[_transaction];
              if (tr.request.from_tag === fromTag && tr.request.call_id === call_id && tr.request.cseq === cseq) {
                reply(482);
                return false;
              }
            }
          }
        }
      }
      function rfc3261_8_1_3_3() {
        if (message.getHeaders("via").length > 1) {
          logger.debug("more than one Via header field present in the response, dropping the response");
          return false;
        }
      }
      function rfc3261_18_3_response() {
        var len = Utils.str_utf8_length(message.body), contentLength = message.getHeader("content-length");
        if (len < contentLength) {
          logger.debug("message body length is lower than the value in Content-Length header field, dropping the response");
          return false;
        }
      }
      function minimumHeaders() {
        var mandatoryHeaders = ["from", "to", "call_id", "cseq", "via"];
        for (var _i = 0, _mandatoryHeaders = mandatoryHeaders; _i < _mandatoryHeaders.length; _i++) {
          var header = _mandatoryHeaders[_i];
          if (!message.hasHeader(header)) {
            logger.debug("missing mandatory header field : ".concat(header, ", dropping the response"));
            return false;
          }
        }
      }
      function reply(status_code) {
        var vias = message.getHeaders("via");
        var to;
        var response = "SIP/2.0 ".concat(status_code, " ").concat(JsSIP_C.REASON_PHRASE[status_code], "\r\n");
        var _iterator4 = _createForOfIteratorHelper(vias), _step4;
        try {
          for (_iterator4.s(); !(_step4 = _iterator4.n()).done; ) {
            var via = _step4.value;
            response += "Via: ".concat(via, "\r\n");
          }
        } catch (err) {
          _iterator4.e(err);
        } finally {
          _iterator4.f();
        }
        to = message.getHeader("To");
        if (!message.to_tag) {
          to += ";tag=".concat(Utils.newTag());
        }
        response += "To: ".concat(to, "\r\n");
        response += "From: ".concat(message.getHeader("From"), "\r\n");
        response += "Call-ID: ".concat(message.call_id, "\r\n");
        response += "CSeq: ".concat(message.cseq, " ").concat(message.method, "\r\n");
        response += "\r\n";
        transport.send(response);
      }
    }
  });

  // node_modules/jssip/lib-es5/Config.js
  var require_Config = __commonJS({
    "node_modules/jssip/lib-es5/Config.js"(exports) {
      "use strict";
      function _createForOfIteratorHelper(o, allowArrayLike) {
        var it;
        if (typeof Symbol === "undefined" || o[Symbol.iterator] == null) {
          if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") {
            if (it) o = it;
            var i = 0;
            var F = function F2() {
            };
            return { s: F, n: function n() {
              if (i >= o.length) return { done: true };
              return { done: false, value: o[i++] };
            }, e: function e(_e) {
              throw _e;
            }, f: F };
          }
          throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.");
        }
        var normalCompletion = true, didErr = false, err;
        return { s: function s() {
          it = o[Symbol.iterator]();
        }, n: function n() {
          var step = it.next();
          normalCompletion = step.done;
          return step;
        }, e: function e(_e2) {
          didErr = true;
          err = _e2;
        }, f: function f() {
          try {
            if (!normalCompletion && it["return"] != null) it["return"]();
          } finally {
            if (didErr) throw err;
          }
        } };
      }
      function _unsupportedIterableToArray(o, minLen) {
        if (!o) return;
        if (typeof o === "string") return _arrayLikeToArray(o, minLen);
        var n = Object.prototype.toString.call(o).slice(8, -1);
        if (n === "Object" && o.constructor) n = o.constructor.name;
        if (n === "Map" || n === "Set") return Array.from(o);
        if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen);
      }
      function _arrayLikeToArray(arr, len) {
        if (len == null || len > arr.length) len = arr.length;
        for (var i = 0, arr2 = new Array(len); i < len; i++) {
          arr2[i] = arr[i];
        }
        return arr2;
      }
      var Utils = require_Utils();
      var JsSIP_C = require_Constants();
      var Grammar = require_Grammar();
      var URI = require_URI();
      var Socket = require_Socket();
      var Exceptions = require_Exceptions();
      exports.settings = {
        // SIP authentication.
        authorization_user: null,
        password: null,
        realm: null,
        ha1: null,
        authorization_jwt: null,
        // SIP account.
        display_name: null,
        uri: null,
        contact_uri: null,
        // SIP instance id (GRUU).
        instance_id: null,
        // Preloaded SIP Route header field.
        use_preloaded_route: false,
        // Session parameters.
        session_timers: true,
        session_timers_refresh_method: JsSIP_C.UPDATE,
        session_timers_force_refresher: false,
        no_answer_timeout: 60,
        // Registration parameters.
        register: true,
        register_expires: 600,
        registrar_server: null,
        // Connection options.
        sockets: null,
        connection_recovery_max_interval: JsSIP_C.CONNECTION_RECOVERY_MAX_INTERVAL,
        connection_recovery_min_interval: JsSIP_C.CONNECTION_RECOVERY_MIN_INTERVAL,
        // Global extra headers, to be added to every request and response
        extra_headers: null,
        /*
         * Host address.
         * Value to be set in Via sent_by and host part of Contact FQDN.
        */
        via_host: "".concat(Utils.createRandomToken(12), ".invalid")
      };
      var checks = {
        mandatory: {
          sockets: function sockets(_sockets2) {
            var _sockets = [];
            if (Socket.isSocket(_sockets2)) {
              _sockets.push({
                socket: _sockets2
              });
            } else if (Array.isArray(_sockets2) && _sockets2.length) {
              var _iterator = _createForOfIteratorHelper(_sockets2), _step;
              try {
                for (_iterator.s(); !(_step = _iterator.n()).done; ) {
                  var socket = _step.value;
                  if (Object.prototype.hasOwnProperty.call(socket, "socket") && Socket.isSocket(socket.socket)) {
                    _sockets.push(socket);
                  } else if (Socket.isSocket(socket)) {
                    _sockets.push({
                      socket
                    });
                  }
                }
              } catch (err) {
                _iterator.e(err);
              } finally {
                _iterator.f();
              }
            } else {
              return;
            }
            return _sockets;
          },
          uri: function uri(_uri) {
            if (!/^sip:/i.test(_uri)) {
              _uri = "".concat(JsSIP_C.SIP, ":").concat(_uri);
            }
            var parsed = URI.parse(_uri);
            if (!parsed) {
              return;
            } else if (!parsed.user) {
              return;
            } else {
              return parsed;
            }
          }
        },
        optional: {
          authorization_user: function authorization_user(_authorization_user) {
            if (Grammar.parse('"'.concat(_authorization_user, '"'), "quoted_string") === -1) {
              return;
            } else {
              return _authorization_user;
            }
          },
          authorization_jwt: function authorization_jwt(_authorization_jwt) {
            if (typeof _authorization_jwt === "string") {
              return _authorization_jwt;
            }
          },
          user_agent: function user_agent(_user_agent) {
            if (typeof _user_agent === "string") {
              return _user_agent;
            }
          },
          connection_recovery_max_interval: function connection_recovery_max_interval(_connection_recovery_max_interval) {
            if (Utils.isDecimal(_connection_recovery_max_interval)) {
              var value = Number(_connection_recovery_max_interval);
              if (value > 0) {
                return value;
              }
            }
          },
          connection_recovery_min_interval: function connection_recovery_min_interval(_connection_recovery_min_interval) {
            if (Utils.isDecimal(_connection_recovery_min_interval)) {
              var value = Number(_connection_recovery_min_interval);
              if (value > 0) {
                return value;
              }
            }
          },
          contact_uri: function contact_uri(_contact_uri) {
            if (typeof _contact_uri === "string") {
              var uri = Grammar.parse(_contact_uri, "SIP_URI");
              if (uri !== -1) {
                return uri;
              }
            }
          },
          display_name: function display_name(_display_name) {
            return _display_name;
          },
          instance_id: function instance_id(_instance_id) {
            if (/^uuid:/i.test(_instance_id)) {
              _instance_id = _instance_id.substr(5);
            }
            if (Grammar.parse(_instance_id, "uuid") === -1) {
              return;
            } else {
              return _instance_id;
            }
          },
          no_answer_timeout: function no_answer_timeout(_no_answer_timeout) {
            if (Utils.isDecimal(_no_answer_timeout)) {
              var value = Number(_no_answer_timeout);
              if (value > 0) {
                return value;
              }
            }
          },
          session_timers: function session_timers(_session_timers) {
            if (typeof _session_timers === "boolean") {
              return _session_timers;
            }
          },
          session_timers_refresh_method: function session_timers_refresh_method(method) {
            if (typeof method === "string") {
              method = method.toUpperCase();
              if (method === JsSIP_C.INVITE || method === JsSIP_C.UPDATE) {
                return method;
              }
            }
          },
          session_timers_force_refresher: function session_timers_force_refresher(_session_timers_force_refresher) {
            if (typeof _session_timers_force_refresher === "boolean") {
              return _session_timers_force_refresher;
            }
          },
          password: function password(_password) {
            return String(_password);
          },
          realm: function realm(_realm) {
            return String(_realm);
          },
          ha1: function ha1(_ha) {
            return String(_ha);
          },
          register: function register(_register) {
            if (typeof _register === "boolean") {
              return _register;
            }
          },
          register_expires: function register_expires(_register_expires) {
            if (Utils.isDecimal(_register_expires)) {
              var value = Number(_register_expires);
              if (value > 0) {
                return value;
              }
            }
          },
          registrar_server: function registrar_server(_registrar_server) {
            if (!/^sip:/i.test(_registrar_server)) {
              _registrar_server = "".concat(JsSIP_C.SIP, ":").concat(_registrar_server);
            }
            var parsed = URI.parse(_registrar_server);
            if (!parsed) {
              return;
            } else if (parsed.user) {
              return;
            } else {
              return parsed;
            }
          },
          use_preloaded_route: function use_preloaded_route(_use_preloaded_route) {
            if (typeof _use_preloaded_route === "boolean") {
              return _use_preloaded_route;
            }
          },
          extra_headers: function extra_headers(_extra_headers) {
            var _extraHeaders = [];
            if (Array.isArray(_extra_headers) && _extra_headers.length) {
              var _iterator2 = _createForOfIteratorHelper(_extra_headers), _step2;
              try {
                for (_iterator2.s(); !(_step2 = _iterator2.n()).done; ) {
                  var header = _step2.value;
                  if (typeof header === "string") {
                    _extraHeaders.push(header);
                  }
                }
              } catch (err) {
                _iterator2.e(err);
              } finally {
                _iterator2.f();
              }
            } else {
              return;
            }
            return _extraHeaders;
          }
        }
      };
      exports.load = function(dst, src) {
        for (var parameter in checks.mandatory) {
          if (!src.hasOwnProperty(parameter)) {
            throw new Exceptions.ConfigurationError(parameter);
          } else {
            var value = src[parameter];
            var checked_value = checks.mandatory[parameter](value);
            if (checked_value !== void 0) {
              dst[parameter] = checked_value;
            } else {
              throw new Exceptions.ConfigurationError(parameter, value);
            }
          }
        }
        for (var _parameter in checks.optional) {
          if (src.hasOwnProperty(_parameter)) {
            var _value = src[_parameter];
            if (Utils.isEmpty(_value)) {
              continue;
            }
            var _checked_value = checks.optional[_parameter](_value);
            if (_checked_value !== void 0) {
              dst[_parameter] = _checked_value;
            } else {
              throw new Exceptions.ConfigurationError(_parameter, _value);
            }
          }
        }
      };
    }
  });

  // node_modules/jssip/lib-es5/UA.js
  var require_UA = __commonJS({
    "node_modules/jssip/lib-es5/UA.js"(exports, module) {
      "use strict";
      function _typeof(obj) {
        "@babel/helpers - typeof";
        if (typeof Symbol === "function" && typeof Symbol.iterator === "symbol") {
          _typeof = function _typeof2(obj2) {
            return typeof obj2;
          };
        } else {
          _typeof = function _typeof2(obj2) {
            return obj2 && typeof Symbol === "function" && obj2.constructor === Symbol && obj2 !== Symbol.prototype ? "symbol" : typeof obj2;
          };
        }
        return _typeof(obj);
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      function _inherits(subClass, superClass) {
        if (typeof superClass !== "function" && superClass !== null) {
          throw new TypeError("Super expression must either be null or a function");
        }
        subClass.prototype = Object.create(superClass && superClass.prototype, { constructor: { value: subClass, writable: true, configurable: true } });
        if (superClass) _setPrototypeOf(subClass, superClass);
      }
      function _setPrototypeOf(o, p) {
        _setPrototypeOf = Object.setPrototypeOf || function _setPrototypeOf2(o2, p2) {
          o2.__proto__ = p2;
          return o2;
        };
        return _setPrototypeOf(o, p);
      }
      function _createSuper(Derived) {
        var hasNativeReflectConstruct = _isNativeReflectConstruct();
        return function _createSuperInternal() {
          var Super = _getPrototypeOf(Derived), result;
          if (hasNativeReflectConstruct) {
            var NewTarget = _getPrototypeOf(this).constructor;
            result = Reflect.construct(Super, arguments, NewTarget);
          } else {
            result = Super.apply(this, arguments);
          }
          return _possibleConstructorReturn(this, result);
        };
      }
      function _possibleConstructorReturn(self, call) {
        if (call && (_typeof(call) === "object" || typeof call === "function")) {
          return call;
        }
        return _assertThisInitialized(self);
      }
      function _assertThisInitialized(self) {
        if (self === void 0) {
          throw new ReferenceError("this hasn't been initialised - super() hasn't been called");
        }
        return self;
      }
      function _isNativeReflectConstruct() {
        if (typeof Reflect === "undefined" || !Reflect.construct) return false;
        if (Reflect.construct.sham) return false;
        if (typeof Proxy === "function") return true;
        try {
          Date.prototype.toString.call(Reflect.construct(Date, [], function() {
          }));
          return true;
        } catch (e) {
          return false;
        }
      }
      function _getPrototypeOf(o) {
        _getPrototypeOf = Object.setPrototypeOf ? Object.getPrototypeOf : function _getPrototypeOf2(o2) {
          return o2.__proto__ || Object.getPrototypeOf(o2);
        };
        return _getPrototypeOf(o);
      }
      var EventEmitter = require_events().EventEmitter;
      var Logger = require_Logger();
      var JsSIP_C = require_Constants();
      var Registrator = require_Registrator();
      var RTCSession = require_RTCSession();
      var Message = require_Message();
      var Options = require_Options();
      var Transactions = require_Transactions();
      var Transport = require_Transport();
      var Utils = require_Utils();
      var Exceptions = require_Exceptions();
      var URI = require_URI();
      var Parser = require_Parser();
      var SIPMessage = require_SIPMessage();
      var sanityCheck = require_sanityCheck();
      var config = require_Config();
      var logger = new Logger("UA");
      var C = {
        // UA status codes.
        STATUS_INIT: 0,
        STATUS_READY: 1,
        STATUS_USER_CLOSED: 2,
        STATUS_NOT_READY: 3,
        // UA error codes.
        CONFIGURATION_ERROR: 1,
        NETWORK_ERROR: 2
      };
      module.exports = /* @__PURE__ */ function(_EventEmitter) {
        _inherits(UA, _EventEmitter);
        var _super = _createSuper(UA);
        _createClass(UA, null, [{
          key: "C",
          // Expose C object.
          get: function get() {
            return C;
          }
        }]);
        function UA(configuration) {
          var _this;
          _classCallCheck(this, UA);
          logger.debug("new() [configuration:%o]", configuration);
          _this = _super.call(this);
          _this._cache = {
            credentials: {}
          };
          _this._configuration = Object.assign({}, config.settings);
          _this._dynConfiguration = {};
          _this._dialogs = {};
          _this._applicants = {};
          _this._sessions = {};
          _this._transport = null;
          _this._contact = null;
          _this._status = C.STATUS_INIT;
          _this._error = null;
          _this._transactions = {
            nist: {},
            nict: {},
            ist: {},
            ict: {}
          };
          _this._data = {};
          _this._closeTimer = null;
          if (configuration === void 0) {
            throw new TypeError("Not enough arguments");
          }
          try {
            _this._loadConfig(configuration);
          } catch (e) {
            _this._status = C.STATUS_NOT_READY;
            _this._error = C.CONFIGURATION_ERROR;
            throw e;
          }
          _this._registrator = new Registrator(_assertThisInitialized(_this));
          return _this;
        }
        _createClass(UA, [{
          key: "start",
          // =================
          //  High Level API
          // =================
          /**
           * Connect to the server if status = STATUS_INIT.
           * Resume UA after being closed.
           */
          value: function start() {
            logger.debug("start()");
            if (this._status === C.STATUS_INIT) {
              this._transport.connect();
            } else if (this._status === C.STATUS_USER_CLOSED) {
              logger.debug("restarting UA");
              if (this._closeTimer !== null) {
                clearTimeout(this._closeTimer);
                this._closeTimer = null;
                this._transport.disconnect();
              }
              this._status = C.STATUS_INIT;
              this._transport.connect();
            } else if (this._status === C.STATUS_READY) {
              logger.debug("UA is in READY status, not restarted");
            } else {
              logger.debug("ERROR: connection is down, Auto-Recovery system is trying to reconnect");
            }
            this._dynConfiguration.register = this._configuration.register;
          }
          /**
           * Register.
           */
        }, {
          key: "register",
          value: function register() {
            logger.debug("register()");
            this._dynConfiguration.register = true;
            this._registrator.register();
          }
          /**
           * Unregister.
           */
        }, {
          key: "unregister",
          value: function unregister(options) {
            logger.debug("unregister()");
            this._dynConfiguration.register = false;
            this._registrator.unregister(options);
          }
          /**
           * Get the Registrator instance.
           */
        }, {
          key: "registrator",
          value: function registrator() {
            return this._registrator;
          }
          /**
           * Registration state.
           */
        }, {
          key: "isRegistered",
          value: function isRegistered() {
            return this._registrator.registered;
          }
          /**
           * Connection state.
           */
        }, {
          key: "isConnected",
          value: function isConnected() {
            return this._transport.isConnected();
          }
          /**
           * Make an outgoing call.
           *
           * -param {String} target
           * -param {Object} [options]
           *
           * -throws {TypeError}
           *
           */
        }, {
          key: "call",
          value: function call(target, options) {
            logger.debug("call()");
            var session = new RTCSession(this);
            session.connect(target, options);
            return session;
          }
          /**
           * Send a message.
           *
           * -param {String} target
           * -param {String} body
           * -param {Object} [options]
           *
           * -throws {TypeError}
           *
           */
        }, {
          key: "sendMessage",
          value: function sendMessage(target, body, options) {
            logger.debug("sendMessage()");
            var message = new Message(this);
            message.send(target, body, options);
            return message;
          }
          /**
           * Send a SIP OPTIONS.
           *
           * -param {String} target
           * -param {String} [body]
           * -param {Object} [options]
           *
           * -throws {TypeError}
           *
           */
        }, {
          key: "sendOptions",
          value: function sendOptions(target, body, options) {
            logger.debug("sendOptions()");
            var message = new Options(this);
            message.send(target, body, options);
            return message;
          }
          /**
           * Terminate ongoing sessions.
           */
        }, {
          key: "terminateSessions",
          value: function terminateSessions(options) {
            logger.debug("terminateSessions()");
            for (var idx in this._sessions) {
              if (!this._sessions[idx].isEnded()) {
                this._sessions[idx].terminate(options);
              }
            }
          }
          /**
           * Gracefully close.
           *
           */
        }, {
          key: "stop",
          value: function stop() {
            var _this2 = this;
            logger.debug("stop()");
            this._dynConfiguration = {};
            if (this._status === C.STATUS_USER_CLOSED) {
              logger.debug("UA already closed");
              return;
            }
            this._registrator.close();
            var num_sessions = Object.keys(this._sessions).length;
            for (var session in this._sessions) {
              if (Object.prototype.hasOwnProperty.call(this._sessions, session)) {
                logger.debug("closing session ".concat(session));
                try {
                  this._sessions[session].terminate();
                } catch (error) {
                }
              }
            }
            for (var applicant in this._applicants) {
              if (Object.prototype.hasOwnProperty.call(this._applicants, applicant)) try {
                this._applicants[applicant].close();
              } catch (error) {
              }
            }
            this._status = C.STATUS_USER_CLOSED;
            var num_transactions = Object.keys(this._transactions.nict).length + Object.keys(this._transactions.nist).length + Object.keys(this._transactions.ict).length + Object.keys(this._transactions.ist).length;
            if (num_transactions === 0 && num_sessions === 0) {
              this._transport.disconnect();
            } else {
              this._closeTimer = setTimeout(function() {
                _this2._closeTimer = null;
                _this2._transport.disconnect();
              }, 2e3);
            }
          }
          /**
           * Normalice a string into a valid SIP request URI
           * -param {String} target
           * -returns {JsSIP.URI|undefined}
           */
        }, {
          key: "normalizeTarget",
          value: function normalizeTarget(target) {
            return Utils.normalizeTarget(target, this._configuration.hostport_params);
          }
          /**
           * Allow retrieving configuration and autogenerated fields in runtime.
           */
        }, {
          key: "get",
          value: function get(parameter) {
            switch (parameter) {
              case "authorization_user":
                return this._configuration.authorization_user;
              case "realm":
                return this._configuration.realm;
              case "ha1":
                return this._configuration.ha1;
              case "authorization_jwt":
                return this._configuration.authorization_jwt;
              default:
                logger.warn('get() | cannot get "%s" parameter in runtime', parameter);
                return void 0;
            }
          }
          /**
           * Allow configuration changes in runtime.
           * Returns true if the parameter could be set.
           */
        }, {
          key: "set",
          value: function set(parameter, value) {
            switch (parameter) {
              case "authorization_user": {
                this._configuration.authorization_user = String(value);
                break;
              }
              case "password": {
                this._configuration.password = String(value);
                break;
              }
              case "realm": {
                this._configuration.realm = String(value);
                break;
              }
              case "ha1": {
                this._configuration.ha1 = String(value);
                this._configuration.password = null;
                break;
              }
              case "authorization_jwt": {
                this._configuration.authorization_jwt = String(value);
                break;
              }
              case "display_name": {
                this._configuration.display_name = value;
                break;
              }
              case "extra_headers": {
                this._configuration.extra_headers = value;
                break;
              }
              default:
                logger.warn('set() | cannot set "%s" parameter in runtime', parameter);
                return false;
            }
            return true;
          }
          // ==========================
          // Event Handlers.
          // ==========================
          /**
           * new Transaction
           */
        }, {
          key: "newTransaction",
          value: function newTransaction(transaction) {
            this._transactions[transaction.type][transaction.id] = transaction;
            this.emit("newTransaction", {
              transaction
            });
          }
          /**
           * Transaction destroyed.
           */
        }, {
          key: "destroyTransaction",
          value: function destroyTransaction(transaction) {
            delete this._transactions[transaction.type][transaction.id];
            this.emit("transactionDestroyed", {
              transaction
            });
          }
          /**
           * new Dialog
           */
        }, {
          key: "newDialog",
          value: function newDialog(dialog) {
            this._dialogs[dialog.id] = dialog;
          }
          /**
           * Dialog destroyed.
           */
        }, {
          key: "destroyDialog",
          value: function destroyDialog(dialog) {
            delete this._dialogs[dialog.id];
          }
          /**
           *  new Message
           */
        }, {
          key: "newMessage",
          value: function newMessage(message, data) {
            this._applicants[message] = message;
            this.emit("newMessage", data);
          }
          /**
           *  new Options
           */
        }, {
          key: "newOptions",
          value: function newOptions(message, data) {
            this._applicants[message] = message;
            this.emit("newOptions", data);
          }
          /**
           *  Message destroyed.
           */
        }, {
          key: "destroyMessage",
          value: function destroyMessage(message) {
            delete this._applicants[message];
          }
          /**
           * new RTCSession
           */
        }, {
          key: "newRTCSession",
          value: function newRTCSession(session, data) {
            this._sessions[session.id] = session;
            this.emit("newRTCSession", data);
          }
          /**
           * RTCSession destroyed.
           */
        }, {
          key: "destroyRTCSession",
          value: function destroyRTCSession(session) {
            delete this._sessions[session.id];
          }
          /**
           * Registered
           */
        }, {
          key: "registered",
          value: function registered(data) {
            this.emit("registered", data);
          }
          /**
           * Unregistered
           */
        }, {
          key: "unregistered",
          value: function unregistered(data) {
            this.emit("unregistered", data);
          }
          /**
           * Registration Failed
           */
        }, {
          key: "registrationFailed",
          value: function registrationFailed(data) {
            this.emit("registrationFailed", data);
          }
          // =========================
          // ReceiveRequest.
          // =========================
          /**
           * Request reception
           */
        }, {
          key: "receiveRequest",
          value: function receiveRequest(request) {
            var method = request.method;
            if (request.ruri.user !== this._configuration.uri.user && request.ruri.user !== this._contact.uri.user) {
              logger.debug("Request-URI does not point to us");
              if (request.method !== JsSIP_C.ACK) {
                request.reply_sl(404);
              }
              return;
            }
            if (request.ruri.scheme === JsSIP_C.SIPS) {
              request.reply_sl(416);
              return;
            }
            if (Transactions.checkTransaction(this, request)) {
              return;
            }
            if (method === JsSIP_C.INVITE) {
              new Transactions.InviteServerTransaction(this, this._transport, request);
            } else if (method !== JsSIP_C.ACK && method !== JsSIP_C.CANCEL) {
              new Transactions.NonInviteServerTransaction(this, this._transport, request);
            }
            if (method === JsSIP_C.OPTIONS) {
              if (this.listeners("newOptions").length === 0) {
                request.reply(200);
                return;
              }
              var message = new Options(this);
              message.init_incoming(request);
            } else if (method === JsSIP_C.MESSAGE) {
              if (this.listeners("newMessage").length === 0) {
                request.reply(405);
                return;
              }
              var _message = new Message(this);
              _message.init_incoming(request);
            } else if (method === JsSIP_C.INVITE) {
              if (!request.to_tag && this.listeners("newRTCSession").length === 0) {
                request.reply(405);
                return;
              }
            }
            var dialog;
            var session;
            if (!request.to_tag) {
              switch (method) {
                case JsSIP_C.INVITE:
                  if (window.RTCPeerConnection) {
                    if (request.hasHeader("replaces")) {
                      var replaces = request.replaces;
                      dialog = this._findDialog(replaces.call_id, replaces.from_tag, replaces.to_tag);
                      if (dialog) {
                        session = dialog.owner;
                        if (!session.isEnded()) {
                          session.receiveRequest(request);
                        } else {
                          request.reply(603);
                        }
                      } else {
                        request.reply(481);
                      }
                    } else {
                      session = new RTCSession(this);
                      session.init_incoming(request);
                    }
                  } else {
                    logger.warn("INVITE received but WebRTC is not supported");
                    request.reply(488);
                  }
                  break;
                case JsSIP_C.BYE:
                  request.reply(481);
                  break;
                case JsSIP_C.CANCEL:
                  session = this._findSession(request);
                  if (session) {
                    session.receiveRequest(request);
                  } else {
                    logger.debug("received CANCEL request for a non existent session");
                  }
                  break;
                case JsSIP_C.ACK:
                  break;
                case JsSIP_C.NOTIFY:
                  this.emit("sipEvent", {
                    event: request.event,
                    request
                  });
                  request.reply(200);
                  break;
                default:
                  request.reply(405);
                  break;
              }
            } else {
              dialog = this._findDialog(request.call_id, request.from_tag, request.to_tag);
              if (dialog) {
                dialog.receiveRequest(request);
              } else if (method === JsSIP_C.NOTIFY) {
                session = this._findSession(request);
                if (session) {
                  session.receiveRequest(request);
                } else {
                  logger.debug("received NOTIFY request for a non existent subscription");
                  request.reply(481, "Subscription does not exist");
                }
              } else if (method !== JsSIP_C.ACK) {
                request.reply(481);
              }
            }
          }
          // =================
          // Utils.
          // =================
          /**
           * Get the session to which the request belongs to, if any.
           */
        }, {
          key: "_findSession",
          value: function _findSession(_ref) {
            var call_id = _ref.call_id, from_tag = _ref.from_tag, to_tag = _ref.to_tag;
            var sessionIDa = call_id + from_tag;
            var sessionA = this._sessions[sessionIDa];
            var sessionIDb = call_id + to_tag;
            var sessionB = this._sessions[sessionIDb];
            if (sessionA) {
              return sessionA;
            } else if (sessionB) {
              return sessionB;
            } else {
              return null;
            }
          }
          /**
           * Get the dialog to which the request belongs to, if any.
           */
        }, {
          key: "_findDialog",
          value: function _findDialog(call_id, from_tag, to_tag) {
            var id = call_id + from_tag + to_tag;
            var dialog = this._dialogs[id];
            if (dialog) {
              return dialog;
            } else {
              id = call_id + to_tag + from_tag;
              dialog = this._dialogs[id];
              if (dialog) {
                return dialog;
              } else {
                return null;
              }
            }
          }
        }, {
          key: "_loadConfig",
          value: function _loadConfig(configuration) {
            try {
              config.load(this._configuration, configuration);
            } catch (e) {
              throw e;
            }
            if (this._configuration.display_name === 0) {
              this._configuration.display_name = "0";
            }
            if (!this._configuration.instance_id) {
              this._configuration.instance_id = Utils.newUUID();
            }
            this._configuration.jssip_id = Utils.createRandomToken(5);
            var hostport_params = this._configuration.uri.clone();
            hostport_params.user = null;
            this._configuration.hostport_params = hostport_params.toString().replace(/^sip:/i, "");
            try {
              this._transport = new Transport(this._configuration.sockets, {
                // Recovery options.
                max_interval: this._configuration.connection_recovery_max_interval,
                min_interval: this._configuration.connection_recovery_min_interval
              });
              this._transport.onconnecting = onTransportConnecting.bind(this);
              this._transport.onconnect = onTransportConnect.bind(this);
              this._transport.ondisconnect = onTransportDisconnect.bind(this);
              this._transport.ondata = onTransportData.bind(this);
            } catch (e) {
              logger.warn(e);
              throw new Exceptions.ConfigurationError("sockets", this._configuration.sockets);
            }
            delete this._configuration.sockets;
            if (!this._configuration.authorization_user) {
              this._configuration.authorization_user = this._configuration.uri.user;
            }
            if (!this._configuration.registrar_server) {
              var registrar_server = this._configuration.uri.clone();
              registrar_server.user = null;
              registrar_server.clearParams();
              registrar_server.clearHeaders();
              this._configuration.registrar_server = registrar_server;
            }
            this._configuration.no_answer_timeout *= 1e3;
            if (this._configuration.contact_uri) {
              this._configuration.via_host = this._configuration.contact_uri.host;
            } else {
              this._configuration.contact_uri = new URI("sip", Utils.createRandomToken(8), this._configuration.via_host, null, {
                transport: "ws"
              });
            }
            this._contact = {
              pub_gruu: null,
              temp_gruu: null,
              uri: this._configuration.contact_uri,
              toString: function toString() {
                var options = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
                var anonymous = options.anonymous || null;
                var outbound = options.outbound || null;
                var contact = "<";
                if (anonymous) {
                  contact += this.temp_gruu || "sip:anonymous@anonymous.invalid;transport=ws";
                } else {
                  contact += this.pub_gruu || this.uri.toString();
                }
                if (outbound && (anonymous ? !this.temp_gruu : !this.pub_gruu)) {
                  contact += ";ob";
                }
                contact += ">";
                return contact;
              }
            };
            var writable_parameters = ["authorization_user", "password", "realm", "ha1", "authorization_jwt", "display_name", "register", "extra_headers"];
            for (var parameter in this._configuration) {
              if (Object.prototype.hasOwnProperty.call(this._configuration, parameter)) {
                if (writable_parameters.indexOf(parameter) !== -1) {
                  Object.defineProperty(this._configuration, parameter, {
                    writable: true,
                    configurable: false
                  });
                } else {
                  Object.defineProperty(this._configuration, parameter, {
                    writable: false,
                    configurable: false
                  });
                }
              }
            }
            logger.debug("configuration parameters after validation:");
            for (var _parameter in this._configuration) {
              if (Object.prototype.hasOwnProperty.call(config.settings, _parameter)) {
                switch (_parameter) {
                  case "uri":
                  case "registrar_server":
                    logger.debug("- ".concat(_parameter, ": ").concat(this._configuration[_parameter]));
                    break;
                  case "password":
                  case "ha1":
                  case "authorization_jwt":
                    logger.debug("- ".concat(_parameter, ": NOT SHOWN"));
                    break;
                  default:
                    logger.debug("- ".concat(_parameter, ": ").concat(JSON.stringify(this._configuration[_parameter])));
                }
              }
            }
            return;
          }
        }, {
          key: "C",
          get: function get() {
            return C;
          }
        }, {
          key: "status",
          get: function get() {
            return this._status;
          }
        }, {
          key: "contact",
          get: function get() {
            return this._contact;
          }
        }, {
          key: "configuration",
          get: function get() {
            return this._configuration;
          }
        }, {
          key: "transport",
          get: function get() {
            return this._transport;
          }
        }]);
        return UA;
      }(EventEmitter);
      function onTransportConnecting(data) {
        this.emit("connecting", data);
      }
      function onTransportConnect(data) {
        if (this._status === C.STATUS_USER_CLOSED) {
          return;
        }
        this._status = C.STATUS_READY;
        this._error = null;
        this.emit("connected", data);
        if (this._dynConfiguration.register) {
          this._registrator.register();
        }
      }
      function onTransportDisconnect(data) {
        var client_transactions = ["nict", "ict", "nist", "ist"];
        for (var _i = 0, _client_transactions = client_transactions; _i < _client_transactions.length; _i++) {
          var type = _client_transactions[_i];
          for (var id in this._transactions[type]) {
            if (Object.prototype.hasOwnProperty.call(this._transactions[type], id)) {
              this._transactions[type][id].onTransportError();
            }
          }
        }
        this.emit("disconnected", data);
        this._registrator.onTransportClosed();
        if (this._status !== C.STATUS_USER_CLOSED) {
          this._status = C.STATUS_NOT_READY;
          this._error = C.NETWORK_ERROR;
        }
      }
      function onTransportData(data) {
        var transport = data.transport;
        var message = data.message;
        message = Parser.parseMessage(message, this);
        if (!message) {
          return;
        }
        if (this._status === C.STATUS_USER_CLOSED && message instanceof SIPMessage.IncomingRequest) {
          return;
        }
        if (!sanityCheck(message, this, transport)) {
          return;
        }
        if (message instanceof SIPMessage.IncomingRequest) {
          message.transport = transport;
          this.receiveRequest(message);
        } else if (message instanceof SIPMessage.IncomingResponse) {
          var transaction;
          switch (message.method) {
            case JsSIP_C.INVITE:
              transaction = this._transactions.ict[message.via_branch];
              if (transaction) {
                transaction.receiveResponse(message);
              }
              break;
            case JsSIP_C.ACK:
              break;
            default:
              transaction = this._transactions.nict[message.via_branch];
              if (transaction) {
                transaction.receiveResponse(message);
              }
              break;
          }
        }
      }
    }
  });

  // node_modules/jssip/lib-es5/WebSocketInterface.js
  var require_WebSocketInterface = __commonJS({
    "node_modules/jssip/lib-es5/WebSocketInterface.js"(exports, module) {
      "use strict";
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor)) {
          throw new TypeError("Cannot call a class as a function");
        }
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || false;
          descriptor.configurable = true;
          if ("value" in descriptor) descriptor.writable = true;
          Object.defineProperty(target, descriptor.key, descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        if (protoProps) _defineProperties(Constructor.prototype, protoProps);
        if (staticProps) _defineProperties(Constructor, staticProps);
        return Constructor;
      }
      var Logger = require_Logger();
      var Grammar = require_Grammar();
      var logger = new Logger("WebSocketInterface");
      module.exports = /* @__PURE__ */ function() {
        function WebSocketInterface(url) {
          _classCallCheck(this, WebSocketInterface);
          logger.debug('new() [url:"%s"]', url);
          this._url = url;
          this._sip_uri = null;
          this._via_transport = null;
          this._ws = null;
          var parsed_url = Grammar.parse(url, "absoluteURI");
          if (parsed_url === -1) {
            logger.warn("invalid WebSocket URI: ".concat(url));
            throw new TypeError("Invalid argument: ".concat(url));
          } else if (parsed_url.scheme !== "wss" && parsed_url.scheme !== "ws") {
            logger.warn("invalid WebSocket URI scheme: ".concat(parsed_url.scheme));
            throw new TypeError("Invalid argument: ".concat(url));
          } else {
            this._sip_uri = "sip:".concat(parsed_url.host).concat(parsed_url.port ? ":".concat(parsed_url.port) : "", ";transport=ws");
            this._via_transport = parsed_url.scheme.toUpperCase();
          }
        }
        _createClass(WebSocketInterface, [{
          key: "connect",
          value: function connect() {
            logger.debug("connect()");
            if (this.isConnected()) {
              logger.debug("WebSocket ".concat(this._url, " is already connected"));
              return;
            } else if (this.isConnecting()) {
              logger.debug("WebSocket ".concat(this._url, " is connecting"));
              return;
            }
            if (this._ws) {
              this.disconnect();
            }
            logger.debug("connecting to WebSocket ".concat(this._url));
            try {
              this._ws = new WebSocket(this._url, "sip");
              this._ws.binaryType = "arraybuffer";
              this._ws.onopen = this._onOpen.bind(this);
              this._ws.onclose = this._onClose.bind(this);
              this._ws.onmessage = this._onMessage.bind(this);
              this._ws.onerror = this._onError.bind(this);
            } catch (e) {
              this._onError(e);
            }
          }
        }, {
          key: "disconnect",
          value: function disconnect() {
            logger.debug("disconnect()");
            if (this._ws) {
              this._ws.onopen = function() {
              };
              this._ws.onclose = function() {
              };
              this._ws.onmessage = function() {
              };
              this._ws.onerror = function() {
              };
              this._ws.close();
              this._ws = null;
            }
          }
        }, {
          key: "send",
          value: function send(message) {
            logger.debug("send()");
            if (this.isConnected()) {
              this._ws.send(message);
              return true;
            } else {
              logger.warn("unable to send message, WebSocket is not open");
              return false;
            }
          }
        }, {
          key: "isConnected",
          value: function isConnected() {
            return this._ws && this._ws.readyState === this._ws.OPEN;
          }
        }, {
          key: "isConnecting",
          value: function isConnecting() {
            return this._ws && this._ws.readyState === this._ws.CONNECTING;
          }
          /**
           * WebSocket Event Handlers
           */
        }, {
          key: "_onOpen",
          value: function _onOpen() {
            logger.debug("WebSocket ".concat(this._url, " connected"));
            this.onconnect();
          }
        }, {
          key: "_onClose",
          value: function _onClose(_ref) {
            var wasClean = _ref.wasClean, code = _ref.code, reason = _ref.reason;
            logger.debug("WebSocket ".concat(this._url, " closed"));
            if (wasClean === false) {
              logger.debug("WebSocket abrupt disconnection");
            }
            this.ondisconnect(!wasClean, code, reason);
          }
        }, {
          key: "_onMessage",
          value: function _onMessage(_ref2) {
            var data = _ref2.data;
            logger.debug("received WebSocket message");
            this.ondata(data);
          }
        }, {
          key: "_onError",
          value: function _onError(e) {
            logger.warn("WebSocket ".concat(this._url, " error: "), e);
          }
        }, {
          key: "via_transport",
          get: function get() {
            return this._via_transport;
          },
          set: function set(value) {
            this._via_transport = value.toUpperCase();
          }
        }, {
          key: "sip_uri",
          get: function get() {
            return this._sip_uri;
          }
        }, {
          key: "url",
          get: function get() {
            return this._url;
          }
        }]);
        return WebSocketInterface;
      }();
    }
  });

  // node_modules/jssip/lib-es5/JsSIP.js
  var require_JsSIP = __commonJS({
    "node_modules/jssip/lib-es5/JsSIP.js"(exports, module) {
      "use strict";
      var pkg = require_package();
      var C = require_Constants();
      var Exceptions = require_Exceptions();
      var Utils = require_Utils();
      var UA = require_UA();
      var URI = require_URI();
      var NameAddrHeader = require_NameAddrHeader();
      var Grammar = require_Grammar();
      var WebSocketInterface = require_WebSocketInterface();
      var debug = require_browser()("JsSIP");
      debug("version %s", pkg.version);
      module.exports = {
        C,
        Exceptions,
        Utils,
        UA,
        URI,
        NameAddrHeader,
        WebSocketInterface,
        Grammar,
        // Expose the debug module.
        debug: require_browser(),
        get name() {
          return pkg.title;
        },
        get version() {
          return pkg.version;
        }
      };
    }
  });

  // entry.js
  window.JsSIP = require_JsSIP();
})();
