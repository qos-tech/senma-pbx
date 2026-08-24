/**
 *  This file is part of SNEP.
 *
 *  SNEP is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  SNEP is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with SNEP.  If not, see <http://www.gnu.org/licenses/>.
 */

var server = window.location.host.split(':')[0];
var qmanager_url = 'http://' + server + ':8080/auth/login';
var announce_url = 'http://api.opens.com.br/announce';
var announce_timeout = 3;

function handler(){

  var count = 0;
  var messages = JSON.parse(this.responseText);

  for (var i = 0; i < messages.length; i++) {
    if(messages[i].status === 'unread') count++;
  }
  if(count > 0){
    var element = document.getElementById("notification");
    element.innerHTML = element.innerHTML + count;
    element.classList.add("new-notification");
  }

}


function getNotifications(url, session){
  // console.log('URL:', url);
  // console.log('UUID:', session.uuid);
  var xmlhttp = new XMLHttpRequest();
  if("withCredentials" in xmlhttp){
    xmlhttp.open("GET", url + '/notifications/' + session.uuid);
    xmlhttp.withCredentials = "true";
    xmlhttp.onload = handler;
    xmlhttp.send();
  }else{
    xmlhttp.open("GET", url + '/notifications/' + session.uuid);
    xmlhttp.withCredentials = "true";
    xmlhttp.onload = handler;
    xmlhttp.send();
  }

}

function getAnnounce(language){
  var url = announce_url + '/' + language;
  checkQmanager();
  console.log("Language: %s -> %s", JSON.stringify(language), url);
  var xmlhttp = new XMLHttpRequest();

  if("withCredentials" in xmlhttp){
    xmlhttp.open("GET", url );
    xmlhttp.timeout = announce_timeout * 1000;
    xmlhttp.withCredentials = "true";
    // xmlhttp.addEventListener("error", handlerAnnounce, false);
    xmlhttp.onload = handlerAnnounce;
    xmlhttp.onerror = handlerAnnounce;
    xmlhttp.ontimeout = handlerAnnounce;
    xmlhttp.send();
  }else{
    xmlhttp.open("GET",  url);
    xmlhttp.timeout = announce_timeout * 1000;
    xmlhttp.withCredentials = "true";
    xmlhttp.onload = handlerAnnounce;
    xmlhttp.onerror = handlerAnnounce;
    xmlhttp.ontimeout = handlerAnnounce;
    // xmlhttp.addEventListener("error", handlerAnnounce, false);
    xmlhttp.send();
  }

}

function handlerAnnounce(){

  var element = document.getElementById("announce");
  var imageElement = document.getElementById("announce-img");

  if(this.responseText) {
    console.log("Response:", this.responseText);
    try {
      var response = JSON.parse(this.responseText);
    } catch (e) {
      var response = {};
    }
    var data = {
      image: response.image || null,
      link: response.link || null,
      text: response.text || null
    }
    if(data.image && data.link){
      element.setAttribute("href",data.link);
      element.setAttribute("alt",data.text);
      imageElement.setAttribute("src",data.image);
    }else{
        useDefaultAnnounce();
    }

  }else{
    useDefaultAnnounce();

  }

}

function useDefaultAnnounce(){

  console.log('Using default announce');
  var element = document.getElementById("announce");
  var imageElement = document.getElementById("announce-img");
  element.setAttribute("href","http://www.opens.com.br/solutions/qmanager");
  imageElement.setAttribute("src", "/snep/images/qmanager-banner.png");

}

function handlerQmanager(){

  var element = document.getElementById("announce-qmanager");
  var imageElement = document.getElementById("announce-login");
  if(!this.status || this.status !== 200) {
    console.log("Disabling announce login");
    element.style.display = 'none';
  }else{
    imageElement.setAttribute("src","/snep/images/qmanager-login.png");
    element.setAttribute("href",qmanager_url);

  }

}
function checkQmanager(){
  var xmlhttp = new XMLHttpRequest();

  xmlhttp.open("GET",  qmanager_url);
  xmlhttp.withCredentials = "true";
  xmlhttp.onload = handlerQmanager;
  xmlhttp.onerror = handlerQmanager;
  xmlhttp.send();


}
