<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
// Get  MySQL data conection 
$settings = parse_ini_file('/var/www/html/snep/includes/setup.conf');
$host = $settings['db.host'] ;
$user = $settings['db.username'];
$pwd  = $settings['db.password'];
$db   = $settings['db.dbname'];
try {       
   $conn = new PDO('mysql:host='.$host.';dbname='.$db, $user, $pwd) ;
   $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    echo $e->getMessage();
    exit ;
}

// Remove index
$sql = "alter table peers drop foreign key `peers_ibfk_1` ; ";
$sql .= "alter table peers drop foreign key `peers_ibfk_2` ; ";
$stmd = $conn->prepare($sql) ;
$stmd->execute() ;
$stmd->closeCursor();

// GEt groups list
$sql = "select id,name,`group` from peers where peer_type = 'R'";
$stmt = $conn->prepare($sql) ;
$stmt->execute();
$data = $stmt->fetchAll() ;
$stmt->closeCursor();
foreach ($data as $row) {
    $grupo = check_group($row['group']) ;
    // Ajusta grupos de ramais x rtamais
    $sql = 'select * from core_peer_groups where peer_id='.$row['id'].' AND group_id='.$grupo ;
    $scc = $conn->query($sql) ;
    $res = $scc->fetchAll() ;
    if (  count($res) === 0 ) {
       $sql = 'insert into core_peer_groups (`peer_id`,`group_id`) values ('.$row['id'].','.$grupo.')' ;
        $sci = $conn->prepare($sql) ;
        $sci->execute() ;
        $sci->closeCursor();
    } 
    // Ajusta regras de negocio
    $sql = "select id,origem,destino from regras_negocio where origem like '%G:%' or destino like '%G:%'" ;
    $scr =  $conn->query($sql) ;
    while($row_rn = $scr->fetch()) {
        $teste=preg_match('/'.$row['group'].'/',$row_rn['origem']) ;
        if ($teste === 1) { 
           altera_regra_negocio('origem', $row_rn['id'],$row['group'],$grupo, $row_rn['origem'] );
        }
        $teste1=preg_match('/'.$row['group'].'/',$row_rn['destino']) ;
        if ($teste1 === 1) { 
           altera_regra_negocio('destino', $row_rn['id'],$row['group'],$grupo,$row_rn['destino']);
        }
        $teste2=preg_match('/all/',$row_rn['origem']) ;
        if ($teste2 === 1) { 
           altera_regra_negocio('origem', $row_rn['id'],'all',1, $row_rn['origem'] );
        }
        $teste3=preg_match('/all/',$row_rn['destino']) ;
        if ($teste3 === 1) { 
           altera_regra_negocio('destino', $row_rn['id'],'all',1,$row_rn['destino']);
        }
    }
} 
$sql = "alter table peers drop column `group` ; drop table `groups`;";
$sci = $conn->prepare($sql) ;
$sci->execute() ;

function altera_regra_negocio($tipo,$id,$name,$grupo,$valor) {
   global $conn ;
   $result = preg_replace("/G\:".$name."/i", "G:".$grupo, $valor);
   $sql='Update regras_negocio set '.$tipo.'="'.$result.'"where id='.$id ;
   $scrn = $conn->prepare($sql) ;
   $scrn->execute() ;
   $scrn->closeCursor();
}


function check_group($name) {
   global $conn ;
   if ($name === "admin" || $name === "all" || $name === "users" || $name === "NULL") 
      return 1 ;
   $stmt = $conn->query('Select id from core_groups where `name` = "'.$name.'"') ;
   $res = $stmt->fetchAll() ;
   if (count($res) > 0) { 
      $gid=$res[0][0];
   } else {
      $stmt = $conn->prepare('insert into  core_groups (`name`) values ("'.$name.'")') ;
      $stmt->execute() ;
      $stmt->closeCursor();
      $gid = $conn->lastInsertId();
   } 
   return $gid ;
   
}     
?>


