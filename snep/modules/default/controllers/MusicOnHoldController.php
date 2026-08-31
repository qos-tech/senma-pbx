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
 * Music on Hold Controller
 *
 * @category  Snep
 * @package   Snep
 * @copyright Copyright (c) 2014 OpenS Tecnologia
 * @author    Opens Tecnologia <desenvolvimento@opens.com.br>
 */
class MusicOnHoldController extends Zend_Controller_Action {

    /**
     * Initial settings of the class
     */
    public function init() {

        $this->view->baseUrl = Zend_Controller_Front::getInstance()->getBaseUrl();
        $this->view->key = Snep_Dashboard_Manager::getKey(
            Zend_Controller_Front::getInstance()->getRequest()->getModuleName(),
            Zend_Controller_Front::getInstance()->getRequest()->getControllerName(),
            Zend_Controller_Front::getInstance()->getRequest()->getActionName());
        $this->modes = array(
            'files' => $this->view->translate('Directory')
            // 'mp3' => $this->view->translate('MP3'),
            // 'quietmp3' => $this->view->translate('Normal'),
            // 'mp3nb' => $this->view->translate('Without buffer'),
            // 'quietmp3nb' => $this->view->translate('Without buffer quiet'),
            // 'custom' => $this->view->translate('Custom application')
            );
        $this->view->lineNumber = Zend_Registry::get('config')->ambiente->linelimit;
        $this->view->url = $this->getFrontController()->getBaseUrl() . "/" . $this->getRequest()->getControllerName();
        $this->view->path_base = Zend_Registry::get('config')->system->path->asterisk->moh;
    }

    /**
     * indexAction - List all Music on Hold sounds
     */
    public function indexAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions")));

        // PHP 8 compatibility: syncFiles() uses $this internally, so it
        // must be called on an instance, not statically (TASK-0002 P1-B).
        // See docs/tasks/0002-php84-compatibility-baseline.md.
        $soundFiles = new Snep_SoundFiles_Manager();
        $soundFiles->syncFiles('moh');

        $sections = Snep_SoundFiles_Manager::getClasses();

        // Count number of files in each section/class
        foreach ($sections as $key => $value) {
            $dir = $value['directory'];
            if (is_dir($dir)) {
                $count = 0 ;
                $scanned_directory = array_diff(scandir($dir), array('..', '.', 'backup', 'tmp'));
                foreach ($scanned_directory as $sd_key => $sd_value) {
                    if (is_dir($dir . '/' . $sd_value)) {
                        continue ;
                    } else {
                        $count ++ ;
                    }
                }
                $sections[$key]['count'] = $count;
            } else {
                $sections[$key]['count'] = 'ND' ;
            }
        }

        $this->view->modes = $this->modes;
        $this->view->sections = $sections;

    }

    /**
     *  addAction - Add Sound File
     */
    public function addAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Add")));

        $viewModes = "";
        foreach($this->modes as $key => $value){
            $viewModes .= "<option value='".$key . "'>".$value." </option>\n";

        }
        //Define the action and load form
        $this->view->modes = $viewModes ;
        $this->view->action = "add" ;
        $this->renderScript( 'music-on-hold/addedit.phtml' );

        if ($this->_request->getPost()) {

            $dados = $this->_request->getParams();
            $classes = Snep_SoundFiles_Manager::getClasses();
            $form_isValid = true;

            // TASK-0026D (F3 sibling): $dados['base']/'directory'] used
            // to be trusted verbatim from the request and joined
            // straight into a path handed to
            // Snep_SoundFiles_Manager::addClass(), which shells out
            // (exec("mkdir ...")) using that path -- the same
            // unparameterized-shell-command root cause as F3's confirmed
            // addfileAction()/removefileAction() findings. "base" is
            // meant to be this app's own fixed MOH root (the view's own
            // "Default path" field is rendered disabled, read-only) --
            // never trust the client for it, always use the server's
            // own configured value. "directory" is meant to be a bare
            // folder name (see the view's client-side "lettersonly"
            // rule, which is not itself a security control since it is
            // trivially bypassed by posting directly); enforce that
            // narrower shape server-side against a fixed allowlist that
            // also makes traversal via "/" or ".." structurally
            // impossible once joined onto the trusted root.
            $dados['base'] = Zend_Registry::get('config')->system->path->asterisk->moh;
            if (!Snep_SoundFiles_Manager::isSafeDirectoryName($dados['directory'])) {
                $message = $this->view->translate('Directory name is invalid.');
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                $form_isValid = false;
            } elseif (file_exists($dados['directory'])) {
                $message = $this->view->translate('Directory already exists');
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                $form_isValid = false;
            }

            foreach ($classes as $name => $item) {

                if ($item['name'] == $dados['name']) {
                    $message = $this->view->translate('Music on hold class already exists');
                    $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                    $form_isValid = false;
                }

                $fullPath = $dados['base'] . $dados['directory'];
                
                if ($item['directory'] == $fullPath) {
                    $message = $this->view->translate('Directory already exists');
                    $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                    $form_isValid = false;
                }
            }

            if ($form_isValid) {
                $dados['directory'] = $dados['base'] .'/' . $dados['directory'];
                $dados['name'] = $dados['nome'];
                Snep_SoundFiles_Manager::addClass($dados);
                $this->_redirect($this->getRequest()->getControllerName());
            }
        }
        
    }

    /**
     * Edit Section/Class
     */
    public function editAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Edit")));

        $section = $this->_request->getParam("section");
        $data = Snep_SoundFiles_Manager::getClasse($section);

        $viewModes = "";
        foreach($this->modes as $key => $value){
            $viewModes .= ($key == $data['mode']) ? "<option value='".$key . "' selected >".$value." </option>\n": "<option value='".$key . "'>".$value." </option>\n";
        }

        $this->view->modes = $viewModes;

        $directory = explode("/", $data['directory']);
        $directoryName = array_pop($directory);

        $this->view->directoryName = $directoryName;
        $originalName = $data['name'];
        
        $this->view->file = $data;

        //Define the action and load form
        $this->view->disabled = 'disabled';
        $this->view->action = "edit" ;
        $this->renderScript( 'music-on-hold/addedit.phtml' );

        if ($this->_request->getPost()) {

            $dados = $this->_request->getParams();

            // TASK-0026D (F3 sibling): same reasoning as addAction()
            // above -- 'directory' here does not itself reach exec(),
            // but it is stored into snep-musiconhold.conf and later
            // read back by removeClass()/addfileAction(), which do. The
            // "folder" field is also rendered disabled/read-only in the
            // edit form (this action is not meant to let a class's
            // directory be changed at all), so a value that fails this
            // check is necessarily not a legitimate submission.
            $mohRoot = Zend_Registry::get('config')->system->path->asterisk->moh;
            if (!Snep_SoundFiles_Manager::isSafeDirectoryName($dados['folder'])) {
                $message = $this->view->translate('Directory name is invalid.');
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
            } else {
                $class = array(
                    'name' => $dados['nome'],
                    'mode' => $dados['mode'],
                    'directory' => $mohRoot.'/'.$dados['folder']);

                Snep_SoundFiles_Manager::editClass($data['name'], $class);

                $this->_redirect($this->getRequest()->getControllerName());
            }
        }

    }

    /**
     * Remove a Carrier
     */
    public function removeAction() {

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Remove")));

        $file = $this->_request->getParam('section');

        $this->view->class = Snep_SoundFiles_Manager::getClasse($file);
        $this->view->message = $this->view->translate("You are removing a music on hold class, it has some audio files attached to it.");
        $this->view->confirmation = $this->view->translate("Delete Sound Files?");
        $this->view->id = $file;

        
        if ($this->_request->getPost()) {
            
            if ($_POST['delete']) {
                $class = Snep_SoundFiles_Manager::getClasse($_POST['id']);
                Snep_SoundFiles_Manager::removeClass($class);
            }
            $this->_redirect($this->getRequest()->getControllerName());
            
        }
        
    }

    /**
     * fileAction
     */
    public function fileAction() {

        $section = $this->_request->getParam('section');

        $this->view->url = $this->getFrontController()->getBaseUrl() . "/" .
                $this->getRequest()->getControllerName();

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Files")));

        $class = Snep_SoundFiles_Manager::getClasse($section);
        // PHP 8 compatibility: getClassFiles() uses $this internally, so
        // it must be called on an instance (TASK-0002 P1-B). See
        // docs/tasks/0002-php84-compatibility-baseline.md.
        $files = (new Snep_SoundFiles_Manager())->getClassFiles($section);
        
        if(empty($files)){
            $this->view->error_message = $this->view->translate("You do not have registered file. <br><br> Click 'Add File' to make the first registration");
        }

        $this->view->files = $files;
        $this->view->section = $section;
    
    }

    /**
     * AddfileAction - Add file
     */
    public function addfileAction() {

        $className = $this->_request->getParam('section');

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Add File")));

        $this->view->section = $className;
        
        if ($this->_request->getPost()) {

            $dados = $this->_request->getParams();
            $data = $_FILES["inputFile"];

            // PHP 8 compatibility: get()/addClassFile() below use $this
            // internally, so they must be called on an instance
            // (TASK-0002 P1-B). See
            // docs/tasks/0002-php84-compatibility-baseline.md.
            $soundFiles = new Snep_SoundFiles_Manager();

            // Converter megabytes em bytes
            $size_in_mega = ini_get('upload_max_filesize');
            $size_in_bytes = Snep_SoundFiles_Manager::converter($size_in_mega);
            
            // Information about section/class
            $class = Snep_SoundFiles_Manager::getClasse($dados['section']);
            $form_isValid = true;

            // TASK-0026D (F3 sibling): $dados['section'] used to be
            // trusted to resolve to a real, existing class -- an
            // unrecognized value makes getClasse() return an empty
            // array, so $class['directory'] below would coerce to "",
            // landing the upload directly in /tmp instead of inside any
            // MOH class directory (or, previously, this controller's
            // now-removed shell commands). Reject up front instead.
            if (empty($class['directory'])) {
                $message = $this->view->translate('Music on hold class not found.');
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                $form_isValid = false;
            }

            $invalid = array('â', 'ã', 'á', 'à', 'ẽ', 'é', 'è', 'ê', 'í', 'ì', 'ó', 'õ', 'ò', 'ú', 'ù', 'ç', " ", '@', '!');
            $valid = array('a', 'a', 'a', 'a', 'e', 'e', 'e', 'e', 'i', 'i', 'o', 'o', 'o', 'u', 'u', 'c', "_", '_', '_');

            if ($data["size"] > $size_in_bytes) {
                $this->view->error_message = $this->view->translate("File larger than $size_in_mega");
                $this->renderScript('error/sneperror.phtml');
            }

            if ($data["type"] != "audio/wav" && $data["type"] != "audio/mp3") {
                $message = "Tamanho ou formato inválido";
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
            }

            $originalName = str_replace($invalid, $valid, $_FILES['inputFile']['name']);
            $clean_name = strstr($originalName, '.', true);
            $validname = $clean_name . '.wav';

            // TASK-0026D (F3): same allowlist as SoundFilesController's
            // F2 fix -- the char-substitution above only replaces a
            // curated set of accented characters/space/@/!, it does not
            // reject shell metacharacters, and $originalName reaches
            // exec("mv/sox ...") below and is used to build every
            // filesystem path for this upload.
            if (!Snep_SoundFiles_Manager::isSafeFilename($originalName)) {
                $this->view->error_message = $this->view->translate("File name is invalid.");
                $this->renderScript('error/sneperror.phtml');
                $form_isValid = false;
            }

            $files = $soundFiles->get($originalName);

            if ($files) {
                $this->view->error_message = $this->view->translate("File already exists");
                $this->renderScript('error/sneperror.phtml');
                $form_isValid = false;
            }

            if ($form_isValid) {


                $uploadName = $data['tmp_name'];
                $arq_tmp = $class['directory'] . "/tmp/" . $originalName;
                $arq_dst = $class['directory'] . "/" . $originalName;

                // TASK-0026D (F3): was exec("mv $uploadName $arq_tmp")
                // -- $uploadName is a PHP-managed upload tmp file, so
                // this is exactly what move_uploaded_file() is for
                // (matching SoundFilesController::addAction()'s own
                // existing pattern for the same operation); no shell at
                // all needed.
                move_uploaded_file($uploadName, $arq_tmp);

                // TASK-0026D (F3): sox is a genuinely external tool with
                // no native PHP equivalent, so it stays an exec() call
                // -- escapeshellarg() is defense-in-depth on top of the
                // isSafeFilename() allowlist enforced above.
                if ($_POST['gsm']) {
                    $fileNe = basename($arq_dst, '.wav');
                    exec("sox " . escapeshellarg($arq_tmp) . " -r 8000 " . escapeshellarg("{$fileNe}.gsm"));
                    $originalName = basename($originalName, '.wav') . ".gsm";
                } else {
                    exec("sox " . escapeshellarg($arq_tmp) . " -r 8000 -c 1 -e signed-integer -b 16 " . escapeshellarg($arq_dst));
                }

                if (file_exists($arq_dst) || file_exists($fileNe)) {
                    $soundFiles->addClassFile(array('arquivo' => $originalName,
                        'descricao' => $dados['description'],
                        'data' => new Zend_Db_Expr('NOW()'),
                        'tipo' => 'MOH',
                        'secao' => $dados['section']));
                } else {
                    $this->view->error_message = $this->view->translate("There were problems uploading the file. Please, contact your system administrator.");
                    $this->renderScript('error/sneperror.phtml');
                }
                $this->_redirect($this->getRequest()->getControllerName() . "/file/section/$className/");
            }
        }
        
    }

    /**
     * editfileAction - Edit file
     */
    public function editfileAction() {

        $fileName = $this->_request->getParam('file');
        $class = $this->_request->getParam('class');

        // PHP 8 compatibility: getClassFile()/editClassFile() use $this
        // internally, so they must be called on an instance (TASK-0002
        // P1-B). See docs/tasks/0002-php84-compatibility-baseline.md.
        $soundFiles = new Snep_SoundFiles_Manager();
        $this->view->file = $soundFiles->getClassFile($fileName,$class) ;

        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Edit File"),
                    $fileName));


        if ($this->_request->getPost()) {

            $dados = $this->_request->getParams();

            $soundFiles->editClassFile($dados);
    
            $this->_redirect($this->getRequest()->getControllerName(). "/file/section/".$dados['secao']);
        }

    }

    /**
     * removefileAction - Remove file
     */
    public function removefileAction() {
        
        $this->view->breadcrumb = Snep_Breadcrumb::renderPath(array(
                    $this->view->translate("Music on Hold Sessions"),
                    $this->view->translate("Delete File")));

        $file = $this->_request->getParam('file');
        $class = $this->_request->getParam('class');
        // PHP 8 compatibility: getClassFile()/remove() use $this
        // internally, so they must be called on an instance (TASK-0002
        // P1-B). See docs/tasks/0002-php84-compatibility-baseline.md.
        $soundFiles = new Snep_SoundFiles_Manager();
        $this->view->file = $soundFiles->getClassFile($file,$class) ;

        $this->view->remove_title = $this->view->translate('Delete music on hold file: '.$file); 
        $this->view->remove_message = $this->view->translate('The music on hold files will be deleted. After that, you have no way get it back.'); 
        $this->view->remove_form = 'music-on-hold'; 
        $this->view->remove_action = 'removefile'; 
        $this->renderScript($this->getRequest()->getControllerName().'/removefile.phtml');

        if ($this->_request->getPost()) {

            $dados = $this->_request->getParams();

            // TASK-0026D (F3): the confirmed finding -- $dados['arquivo']
            // was a raw POST value spliced straight into
            // exec("rm {$file_remove}") with zero sanitization (the
            // second exec() ran unconditionally, with no file_exists()
            // gate at all). $dados['secao'] was equally untrusted,
            // letting $base_dir be built from an arbitrary string with
            // no check that it names a real, existing MOH class.
            // "secao" is validated against the actual finite set of
            // configured class names (a real allowlist, not a made-up
            // one) and "arquivo" against the same filename allowlist
            // used for F2/F3's upload paths -- which also rules out "/"
            // and "..", so $file_remove cannot be steered outside the
            // resolved class directory once both checks pass.
            $validSections = array('default');
            foreach (Snep_SoundFiles_Manager::getClasses() as $existingClass) {
                $validSections[] = $existingClass['name'];
            }
            if (!in_array($dados['secao'], $validSections, true)
                || !Snep_SoundFiles_Manager::isSafeFilename($dados['arquivo'])) {
                $message = $this->view->translate('Invalid file or section.');
                $this->_helper->redirector('sneperror','error',null,array('error_message'=>$message));
                return;
            }

            $base_dir = Zend_Registry::get('config')->system->path->asterisk->moh;
            if ($dados['secao'] != 'default') {
                $base_dir .= '/'.$dados['secao'] ;
            }
            $file_remove = $base_dir . '/' . $dados['arquivo'] ;

            // TASK-0026D (F3): was exec("rm ...") (twice, the second
            // unconditionally) -- unlink() needs no shell at all for a
            // plain file delete; a single, correctly-gated call replaces
            // both.
            if (file_exists($file_remove)) {
                unlink($file_remove);
            }

            $soundFiles->remove($dados['arquivo'], $dados['secao']);

            $this->_redirect($this->getRequest()->getControllerName() . "/file/section/".$dados['secao']);
        }
    }

}
