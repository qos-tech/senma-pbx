<?php

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

/**
 * Notifications Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2015 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class NotificationsController extends Zend_Controller_Action {

    /**
     * List all Notifications
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Notifications")));

        $this->view->url = $this->getFrontController()->getBaseUrl() . '/' . $this->getRequest()->getControllerName();
        $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;

        $options = $this->_request->getParams();

        if($options['id'] == 'all'){

        	$notifications = Snep_Notifications::getAll();
        	if($notifications){
        		$this->view->notifications = $notifications;
        		$this->view->options = 'all';
        	}else{
            $this->view->error_type = 'alert';
            $this->view->error_title = 'Warning';
        		$this->view->error_message = $this->view->translate("You do not have any notifications.");
            $this->renderScript('error/sneperror.phtml');
        	}

        }else{

        	$notification = Snep_Notifications::getNotification($options['id']);

        	$html = array();
        	$cont = 0;

          $active='active';
      		$html[$cont]  = "<div class='item ".$active."'>";
      		$html[$cont] .= "<div class='carousel-content'>";
      		$html[$cont] .= "<div class='panel panel-default col-sm-12 notification-panel'>";
      		$html[$cont] .= "<div class='panel-body'>";
      		$html[$cont] .= "<h2>".$notification->title."</h2>";
      		$html[$cont] .= "<h5>".$notification->from .' - '.date("d/m/Y G:i:s", strtotime($notification->creation_date))."</h5>";
      		$html[$cont] .= "<br><p>".$notification->message."</p>";
      		$html[$cont] .= "<div class='panel-footer clearfix notification-panel'>";
      		$html[$cont] .= "<a href='/snep/index.php/default/notifications?id=all'><span class='notification fa fa-list fa-3x notification-panel'></span></a>&nbsp";
      		$html[$cont] .= "<div class='pull-right'>";

              if(isset($prev_id))
                  $html[$cont] .= "<a href='/snep/index.php/default/notifications?id=".$prev_id . "' data-slide='prev'><span class='notification fa fa-chevron-circle-left fa-3x notification-panel'></span></a>&nbsp";

              if(isset($next_id))
                  $html[$cont] .= "<a href='/snep/index.php/default/notifications?id=".$next_id. "' data-slide='next'><span class='notification fa fa-chevron-circle-right fa-3x notification-panel'></span></a>";


      		$html[$cont] .= "</div>";
      		$html[$cont] .= "</div>";
      		$html[$cont] .= "</div>";
      		$html[$cont] .= "</div>";
      		$html[$cont] .= "</div>";
      		$html[$cont] .= "</div>";
          Snep_Notifications::setRead($options['id']);
          $this->view->html = $html;


        }

    }

    /**
     * Remove a user
     */
    public function removeAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Notification"),
                    $this->view->translate("Delete")));

        $id = $this->_request->getParam('id');

        $this->view->id = $id;
        $this->view->remove_title = $this->view->translate('Delete Notification.');
        $this->view->remove_message = $this->view->translate('The notification will be deleted. After that, you have no way get it back.');
        $this->view->remove_form = 'notifications';
        $this->renderScript('remove/remove.phtml');

        if ($this->_request->getPost()) {

            // remove notification
            Snep_Notifications::removeNotification($id);

            $this->_redirect($this->getRequest()->getControllerName()."?id=all");
        }
    }

}
