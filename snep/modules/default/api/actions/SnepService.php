<?php

/**
 * Interface de Serviços do SNEP
 * Esta interface descreve os metodos e atributos padrões para as classes
 * que farão as ações de serviços do snep.
 */
interface SnepService {
    /**
     * Metodo principal
     * @return Menssagem de ok ou erro.
     */
    public function execute();
}
