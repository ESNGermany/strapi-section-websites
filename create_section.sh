# !/bin/bash

SECTIONNAME="ESN Freiburg"
DOMAIN="freiburg.esn-germany.de"
MAIL="freiburg@esn-germany.de"
SMALLSECTION="esnfreiburg"

# Let's try the environment file for passwords and stuff
source .envcreatescript

# Necessary variables in the .envcreatescript file
#STRAPIDIR=
#STRAPIPM2=
#RANDTOKEN=
#STRAPIDB=
#STRAPIDBUSER=
#STRAPIDBHOST=
#STRAPIDBPORT=
#STRAPIDBPWD=
SECTIONSFILE=${STRAPIDIR}/sections.txt


###################################################################################################
# This function creates a new strapi user for the section.
# As the community edition of strapi doesn't allow to create them through the admin panel, we insert them directly to the database.
function create_strapi_user_group {
	# Create new Strapi User and give the random login token back
	RANDTOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1)
	PGCOMMAND="INSERT INTO strapi_administrator (email, \"registrationToken\") VALUES ('${MAIL}', '${RANDTOKEN}');"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"

	# Create a new role for the new section
	PGCOMMAND="INSERT INTO strapi_role (name, code, description) VALUES ('${SECTIONNAME}', 'section_${SMALLSECTION} ', 'Strapi Account of ${SECTIONNAME}');"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"

	# Adding new user to new role
	# Getting the user_id
	PGCOMMAND="SELECT id FROM strapi_administrator WHERE email = '${MAIL}' LIMIT 1;"
	USERID=$(psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}")
	# Getting the role_id
	PGCOMMAND="SELECT id FROM strapi_role WHERE name = '${SECTIONNAME}' LIMIT 1;"
	ROLEID=$(psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}")
	# Adding user_id to role_id
	PGCOMMAND="INSERT INTO strapi_users_roles (user_id, role_id) VALUES ('${USERID}', '${ROLEID}');"
	ROLEID=$(psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}")

	# We need a restart of Strapi to apply the new roles
	cd ${STRAPIDIR}
	ENV_PATH=${STRAPIDIR}/.env pm2 start yarn --name ${STRAPIPM2} --interpreter bash -- develop 2>&1 1>/dev/null
	pm2 delete ${STRAPIPM2} 2>&1 1>/dev/null
}

function delete_strapi_section {
	echo "This script deletes the section you enter"
	read -p 'Section Name (eg. ESN Freiburg): ' SECTIONNAME
	read -p 'Section Domain (eg. freiburg.esn-germany.de): ' DOMAIN
	read -p 'Mail Address: ' MAIL

	SMALLSECTION=$(echo ${SECTIONNAME} | iconv -f utf8 -t ascii//TRANSLIT | tr -d " " | tr [:upper:] [:lower:])
	echo "${SMALLSECTION}"
	echo -e "Deleting the following sections website: ${SECTIONNAME} \nDomain Address:\t https://${DOMAIN} \nAdmin Mail:\t ${MAIL}"
	read -p 'Do you really want to delete them? [y/N]' INFO

	if [[ $INFO != "y" ]]; then
		echo "Aborting deletion"
		exit 0
	fi

	pm2 delete ${STRAPIPM2} 2>&1 1>/dev/null
	# Adding new user to new role
	# Getting the user_id
	PGCOMMAND="SELECT id FROM strapi_administrator WHERE email = '${MAIL}' LIMIT 1;"
	USERID=$(psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}")
	# Getting the role_id
	PGCOMMAND="SELECT id FROM strapi_role WHERE code = 'section_${SECTIONNAME}' LIMIT 1;"
	ROLEID=$(psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}")
	# Removing user from user role
	PGCOMMAND="DELETE FROM strapi_users_roles WHERE user_id = '${USERID}';"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"
	PGCOMMAND="DELETE FROM strapi_users_roles WHERE role_id = '${ROLEID}';"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"
	# Removing user and group
	PGCOMMAND="DELETE FROM strapi_administrator WHERE email = '${MAIL}';"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"
	PGCOMMAND="DELETE FROM strapi_role WHERE name = '${SECTIONNAME}';"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"

	# Delete all tables from the section
	PGCOMMAND="DO
										\$do\$
DECLARE
   _tbl text;
BEGIN
FOR _tbl  IN
    SELECT quote_ident(table_schema) || '.'
        || quote_ident(table_name)      
    FROM   information_schema.tables
    WHERE  table_name LIKE '${SMALLSECTION}' || '%'  
    AND    table_schema NOT LIKE 'pg\_%'    
LOOP
   EXECUTE 
   'DROP TABLE ' || _tbl;  
END LOOP;
END
\$do\$;"
	psql postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"

	find ${STRAPIDIR}/api/ -type d -name "${SMALLSECTION}-*" -exec rm -r "{}" \; 2>&1 1>/dev/null

	# Start Strapi again
	ENV_PATH=${STRAPIDIR}/.env pm2 start yarn --name ${STRAPIPM2} --interpreter bash -- develop
}

###################################################################################################
function update_sections {
	# Delete all section sites except the template
	find ${STRAPIDIR}/api/ -maxdepth 1 -type d -not -name website-* -not -name api -exec rm -r "{}" \; 2>&1 1>/dev/null
	git pull
	while IFS= read -r line; do 
		SECTIONNAME=$line
		#First copy the template folders for a new section
		find ${STRAPIDIR}/api/ -type d -name website-* |
			while IFS= read -r secpath; do
				NEWPATH=$(echo ${secpath} | sed -r "s/(.*)website-(.*)/\1${SMALLSECTION}-\2/g")
				cp -R ${secpath} ${NEWPATH}
				find ${NEWPATH} -type f -print0 | xargs -0 sed -i -E "s/(.*)website-(.*)/\1${SMALLSECTION}-\2/g"
				find ${NEWPATH} -type f -print0 | xargs -0 sed -i -E "s/(.*)website_(.*)/\1${SMALLSECTION}_\2/g"
				find ${NEWPATH} -type f -print0 | xargs -0 sed -i -E "s/(.*)Website\ (.*)/\1${SECTIONNAME}\ \2/g"
			done
	done < ${SECTIONSFILE}
	echo "Update complete"	
}

###################################################################################################
function add_section_website {
	# Create a lowercase version of the name and remove umlaute
	SMALLSECTION=$(echo ${SECTIONNAME} | iconv -f utf8 -t ascii//TRANSLIT | tr -d " " | tr [:upper:] [:lower:])

	echo "Stopping current Strapi installation"
	pm2 stop ${STRAPIPM2} 

	create_strapi_user_group
	update_sections

	cd ${STRAPIDIR}
	ENV_PATH=${STRAPIDIR}/.env pm2 start yarn --name ${STRAPIPM2} --interpreter bash -- develop

	echo "Send this registration link to the new site admin: https://sections.esn-germany.de/admin/auth/register?registrationToken=${RANDTOKEN}"
	echo "Please go now to the administraton panel and grant the new role access to the following tables:"
	echo "Settings -> Roles -> ${SECTIONNAME}"

	PGCOMMAND="SELECT table_name FROM information_schema.tables WHERE table_name LIKE '%${SMALLSECTION}%';"
	psql -qtAX postgresql://${STRAPIDBUSER}:${STRAPIDBPWD}@${STRAPIDBHOST}:${STRAPIDBPORT}/${STRAPIDB} -c "${PGCOMMAND}"

}

###################################################################################################
function new_section_website {
	echo "This script creates a new section website on the backend and frontend"
	read -p 'Section Name (eg. ESN Freiburg): ' SECTIONNAME
	read -p 'Section Domain (eg. freiburg.esn-germany.de): ' DOMAIN
	read -p 'Mail Address: ' MAIL
	echo -e "Creating a new website for section: ${SECTIONNAME} \nDomain Address:\t https://${DOMAIN} \nAdmin Mail:\t ${MAIL}"
	read -p 'Are the information above correct? [y/N]' INFO

	if [[ $INFO != "y" ]]; then
		echo "Aborting creation"
		exit 0
	fi
	echo ${SECTIONNAME} >> sections.txt
	add_section_website

}

############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options
while getopts ":d:u:n:" option; do
	case $option in
	d) # display Help
		delete_strapi_section
		exit
		;;
	u) # update strapi from github
		update_sections
		exit
		;;
	n) # create new website
		new_section_website
		exit
		;;
	esac
done

printf "Usage of the script ./create_section.sh -n/-u/-d:
	-n to create a new section website 
	-d delete an existing website 
	-u update from github\n"

exit 0
