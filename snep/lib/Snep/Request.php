<?php

/*
	* Class to construct data and send requests to webhooks
*/

class Snep_Request {

	// __construct() is never invoked anywhere in the codebase -- the class
	// is used exclusively via Snep_Request::method() static calls, never
	// `new`'d -- left untouched (dead code, not a PHP 8 compatibility
	// concern). http_context()/send_request()/parseHeaders() below are
	// declared static because every call site already uses :: and none of
	// them reference $this; see docs/tasks/0002-php84-compatibility-baseline.md.
	public function __construct(){
		$this->log = Zend_Registry::get("log");
	}

    // create the http context to prepare data to send the request
    public static function http_context($data,$method="POST"){
        $jdata = json_encode($data);
		if(isset($data['content-type'])){
			$content_type = "Content-type: " . $data['content-type'];
		}else{
			$content_type = "Content-type: application/json";
		}

		if(isset($data['accept-content-type'])){
			$accept_content_type = "Accept: " . $data['accept-content-type'];
		}else{
			$accept_content_type = "Accept: application/json";
		}

        // definindo timeout padrao de conexao com servicos externos
        // timeout em segundos
		if(isset($data['timeout'])){
			$timeout = $data['timeout'];
		}else{
			$timeout = 3;
		}
        $ctx = stream_context_create(array(
                        'http' => array(
                                'header'  => $content_type . "\r\n" . $accept_content_type . "\r\n" . "Connection: close\r\n",
																'ignore_errors' => true,
                                'method'  => $method,
                                'timeout' => $timeout,
                                'content' => $jdata
															),
												'ssl' => array(
												        'verify_peer' => false,
												        'verify_peer_name' => false
												    )
                        )
        );
        //$this->log->debug("Mounting http request: {method:$method,timeout:$timeout,$content_type,$jdata}");
        return $ctx;

    }

    // TASK-0024: send_request()'s contract is now: ALWAYS returns
    // ['response' => string|false, 'response_code' => int], NEVER
    // throws, regardless of which transport phase failed (DNS,
    // connection refused, blackhole timeout, TLS failure -- see
    // docs/tasks/0024-external-api-failure-isolation.md §1/§7/§8/§11).
    // file_get_contents() returning false, or PHP never populating its
    // own magic $http_response_header variable at all, both mean no
    // connection-level response was ever produced. Previously this fell
    // straight into parseHeaders()'s unconditional count($headers), a
    // PHP 8 TypeError on the resulting null. response_code=0 was chosen
    // (not null, not a re-thrown exception) because it is loosely equal
    // to the `case false:` branches every current caller already has
    // for "no connection" (confirmed live: PHP's switch() uses ==, and
    // 0 == false), so every existing caller's own already-written
    // failure handling becomes reachable unchanged -- no caller-side
    // code needed to change. See the implementation section of the doc
    // above for the full caller inventory this was verified against.
    public static function send_request($url,$ctx){
        $raw_response = @file_get_contents($url,0,$ctx);
        if ($raw_response === false || !isset($http_response_header) || !is_array($http_response_header)) {
            return array(
                "response" => false,
                "response_code" => 0,
            );
        }
        $headers = self::parseHeaders($http_response_header);
        $response = array(
            "response" => $raw_response,
            "response_code" => $headers['response_code'] ?? 0,
        );
        return $response;
    }

		// TASK-0024: defensive on its own terms too (not just because its
		// only caller, send_request() above, now never passes it a bad
		// value) -- count() must never receive anything but a real array.
		static function parseHeaders( $headers )	{
		    $head = array();
				if(is_array($headers) && count($headers) > 0){
			    foreach( $headers as $k=>$v )
			    {
			        $t = explode( ':', $v, 2 );
			        if( isset( $t[1] ) )
			            $head[ trim($t[0]) ] = trim( $t[1] );
			        else
			        {
			            $head[] = $v;
			            if( preg_match( "#HTTP/[0-9\.]+\s+([0-9]+)#",$v, $out ) )
			                $head['response_code'] = intval($out[1]);
			        }
			    }
				}
		    return $head;
		}

}
