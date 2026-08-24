#!/bin/sh 
#   This file is part of SNEP
#   Para território Brasileiro leia LICENCA_BR.txt
#   All other countries read the following disclaimer
# 
#   SNEP is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
# 
#   SNEP is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
# 
#   You should have received a copy of the GNU General Public License
#   along with SNEP.  If not, see <http://www.gnu.org/licenses/>.
#
echo "" > messages.po
echo "Fase 1 : Arquivos php/phtml"
find $1 -type f \( -name "*.php" -o -name "*.phtml" \) | grep -v ".git" | grep -v "Zend/" | xgettext --keyword=translate --language=PHP --from-code=utf-8 -j -f -;
echo "" >> messages.po;
echo "Fase 2 : Arquivos xml"
export PYTHONIOENCODING=utf_8;
for file in `find $1 -type f -name *.xml | grep -v .git | grep -v Zend/`; do python findstrings.py -f $file >> messages.po; done;
xgettext -s messages.po
