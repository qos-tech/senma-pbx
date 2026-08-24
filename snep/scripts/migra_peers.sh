#!/bin/bash


if [ -z $1 ]
then
	echo "Voce precisa informar um arquivo de saida"
	echo "Exemplo: $0 [arquivo_de_saida]"
	exit 1
fi

if [ -f $1 ]
then
	echo -en "Este arquivo [$1] já existe! Tem certeza que deseja subscrever seu conteúdo? (s/ n) (default: n) :"
	read answer
	if [ "$answer" != "s" ]
	then
		echo "Saindo"
		exit 0
	else
		echo > $1
	fi
fi

mysql -usnep -psneppass snep -B -e "select name,secret from peers"|grep -v "name\|admin" | while read name pass  
do 
	echo -en "Adding: $name -> $pass -> $allow" 
	echo -en "[${name}]
fromuser=${name}
username=${name}
callerid=Ramal ${name} <${name}>
qualify=yes
type=friend
dtmfmode=rfc2833
nat=force_rport
secret=${pass}
host=dynamic
context=default
disallow=all
allow=ulaw
allow=alaw
\n" >> $1
	echo done 
done

extconfig=`grep "^sippeers" /etc/asterisk/extconfig.conf`
if [ $? -eq 0 ]
then
	echo "Realtime habilitado"
	echo -en "Deseja desabilitar o Realtime para os peers? (s/n) (default: n):"
	read real
	if [ "$real" == "s" ]
	then
		echo -en "Desabilitando o Realtime para os Peers ..."
		sed -i 's/^sippeers/;sippeers/g' /etc/asterisk/extconfig.conf
		sed -i 's/^sipusers/;sipusers/g' /etc/asterisk/extconfig.conf
		echo done
	fi
fi
