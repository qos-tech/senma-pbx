<?php

class Billing_TelcosController extends Zend_Controller_Action {

    /**
     * getForm - Monta formulário
     * @return \Snep_Form_Simple
     */
    protected function getForm() {

        //$form_config = new Zend_Config_Xml('./modules/loguser/forms/log-user.xml', 'general', true);
        //$form = new Snep_Form_Simple($form_config);
        $form = new Snep_Form_Simple();
        $form->setAction($this->getFrontController()->getBaseUrl() . '/billing/billing');


        $form->getElement('submit')->setLabel('Enviar');
        $form->getElement('submit')->removeDecorator('DtDdWrapper');
        $form->getElement('submit')->addDecorator(array("opentd" => 'HtmlTag'), array('class' => 'form_control', "colspan" => 2, 'tag' => 'td'));
        $form->getElement('submit')->addDecorator(array("opentr" => 'HtmlTag'), array('tag' => 'tr'));
        $form->removeElement('cancel');

        return $form;
    }

    /**
     * IndexAction - Monta tela principal
     */
    public function indexAction() {

        $session = new Zend_Session_Namespace("billing");

        $this->view->breadcrumb = $this->view->translate("Billing >> Telcos");
        $this->view->url = $this->getFrontController()->getBaseUrl() . '/billing/telcos';
        $this->view->urlBill = $this->getFrontController()->getBaseUrl() . '/billing/billing';
        $this->view->telcos = Telcos_Manager::getAll();
        //$this->renderScript( $this->getRequest()->getControllerName().'/index.phtml' );

    }

    /**
    * Add Telco Action
    */
    public function addAction(){
      $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                  $this->view->translate("Telcos"),
                  $this->view->translate("Add")));

      $db = Zend_Registry::get('db');

      $this->view->action = "add" ;
      $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

      if ($this->_request->getPost()) {

        $id = Telcos_Manager::add($_POST);
        if(is_int($id)){
          $this->_redirect($this->getRequest()->getModuleName().'/'.$this->getRequest()->getControllerName());
        }else{
          $this->view->error_message = $id;
          $this->renderScript('error/sneperror.phtml');
        }


      }

    }

    /**
    * Edit Telco Action
    */
    public function editAction(){
      $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                  $this->view->translate("Telcos"),
                  $this->view->translate("Edit")));

      $db = Zend_Registry::get('db');

      $this->view->action = "edit" ;
      $id = $this->_request->getParam('id');
      $this->view->telco = Telcos_Manager::get($id);
      $this->renderScript( $this->getRequest()->getControllerName().'/addedit.phtml' );

      if ($this->_request->getPost()) {

        $id = Telcos_Manager::update($_POST);
        if($id){
          $this->_redirect($this->getRequest()->getModuleName().'/'.$this->getRequest()->getControllerName());
        }else{
          $this->view->error_message = $id;
          $this->renderScript('error/sneperror.phtml');
        }


      }

    }

    /**
    * Remove Telco Action
    */
    public function removeAction(){
      $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                  $this->view->translate("Telcos"),
                  $this->view->translate("Remove")));

      $id = $this->_request->getParam('id');


      $this->view->id = $id;
      $this->view->action = 'remove';
      $this->view->remove_title = $this->view->translate('Delete a Telco');
      $this->view->remove_message = $this->view->translate('The Telco will be deleted. After that, you have no way get it back.');
      $this->view->remove_form = 'telcos';
      $this->renderScript('remove/remove.phtml');


        if ($this->_request->getPost()) {

            $result = Telcos_Manager::get($id);
            Telcos_Manager::remove($_POST['id']);
            //log-user
            if (class_exists("Loguser_Manager")) {
                $loguser = array(
                  'table' => 'telcos',
                  'registerid' => $id,
                  'description' => "Deleted Telco $id - {$result['name']}"
                );
                Snep_LogUser::log("delete", $loguser);
            }
            $this->_redirect($this->getRequest()->getModuleName().'/'.$this->getRequest()->getControllerName());
            //$this->_redirect($this->getFrontController()->getBaseUrl() . '/billing/telcos');

        }

    }
}
