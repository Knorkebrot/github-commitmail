#
# BSD Makefile
#

DISTNAME=	github-commitmail

.ifndef PREFIX
.	error "PREFIX needs to be set. E.g. /usr/local"
.endif

install:
.	ifndef INSTALL_SCRIPT
.		error "INSTALL_SCRIPT needs to be set"
.	endif
	${INSTALL_SCRIPT} ${.CURDIR}/${DISTNAME}.pl ${PREFIX}/bin/${DISTNAME}
	${INSTALL_SCRIPT} ${.CURDIR}/${DISTNAME}.conf.sample ${PREFIX}/etc/${DISTNAME}.conf.sample
	[ -f ${PREFIX}/etc/${DISTNAME}.conf ] || touch ${PREFIX}/etc/${DISTNAME}.conf

uninstall:
	/bin/rm ${PREFIX}/bin/${DISTNAME} ${PREFIX}/etc/${DISTNAME}.conf.sample
	[ -e ${PREFIX}/etc/${DISTNAME}.conf -a -s ${PREFIX}/etc/${DISTNAME}.conf ] || /bin/rm ${PREFIX}/etc/${DISTNAME}.conf
	[ ! -f /var/tmp/${DISTNAME} ] || /bin/rm /var/tmp/${DISTNAME}
