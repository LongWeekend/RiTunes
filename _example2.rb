#
# Copyright 2010 Long Weekend LLC
# Written by paul [a.] t longwwekendmobile.com
# Please read the README file
#

##
## domain_keyword : string
## -----------------------
## A single keyword automatically added to each search. Used to narrow your search
## and reduce noise from unrelated apps in result. For example, we use "Japanese" 
## when searching for japanese study apps
##
## keyword_stack : array of strings 
## --------------------------------
## Inidivual and/or compound search terms, more terms takes more time per run
## The 'domain_keyword' string is automatically added to each search.
##
## keyword_stack_no_domain_kw : array of strings
## ---------------------------------------------
## Inidivual and/or compound search terms that do not use the auto-included domain_keyword
##
##-------------------------------------------------------------------------------------------

### Example setup ranking apps relating to the fictional game "Agitated Birds"

domain_keyword = "game"
keyword_stack = ["agitated", "upset", "angry", "bird", "pigeon", "shooting", "skill", "amazing", "best"]
keyword_stack_no_domain_kw = ["agitated birds", "fraggah", "angry hens", "game"]
