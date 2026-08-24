<?php

/*
	* Class to construct data and send requests to webhooks
*/

class Snep_Request {

	public function __construct(){
		$this->log = Zend_Registry::get("log");
	}

    // create the http context to prepare data to send the request
    public function http_context($data,$method="POST"){
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

    // Send the request to the aditional service
    public function send_request($url,$ctx){
        $raw_response = @file_get_contents($url,0,$ctx);
				$headers = self::parseHeaders($http_response_header);
				$response = array(
					"response" => $raw_response,
					"response_code" => $headers['response_code']
				);
        return $response;
    }

		function parseHeaders( $headers )	{
		    $head = array();
				if(count($headers) > 0){
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
