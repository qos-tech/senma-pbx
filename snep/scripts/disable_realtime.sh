#!/bin/bash

# check if Realtime SIP is enabled
extconfig=`grep "^sip" /etc/asterisk/extconfig.conf`
if [ $? -eq 0 ]
then
        echo "SIP Realtime habilitado"
        echo -en "Deseja desabilitar o Realtime para os peers SIP? (s/n) (default: n):"
        read real
        if [ "$real" == "s" ]
        then
                echo -en "Desabilitando o Realtime para os SIP Peers ..."
                sed -i 's/^sippeers/;sippeers/g' /etc/asterisk/extconfig.conf
                sed -i 's/^sipusers/;sipusers/g' /etc/asterisk/extconfig.conf
		echo "Reloading asterisk extconfig module..."
		asterisk -rx "module reload extconfig"
                echo done
	else
		echo "Ignoring SIP Realtime"
        fi
else
	echo "SIP Realtime not enabled"
fi

extconfig=`grep "^iax" /etc/asterisk/extconfig.conf`
if [ $? -eq 0 ]
then
        echo "IAX Realtime habilitado"
        echo -en "Deseja desabilitar o Realtime para os peers IAX? (s/n) (default: n):"
        read iax
        if [ "$iax" == "s" ]
        then
                echo -en "Desabilitando o Realtime para os IAX Peers ..."
                sed -i 's/^iaxpeers/;iaxpeers/g' /etc/asterisk/extconfig.conf
                sed -i 's/^iaxusers/;iaxusers/g' /etc/asterisk/extconfig.conf
		echo "Reloading asterisk extconfig module..."
		asterisk -rx "module reload extconfig"
                echo done
	else
		echo "Ignoring IAX Realtime"
        fi
else
	echo "IAX Realtime not enabled"
fi
