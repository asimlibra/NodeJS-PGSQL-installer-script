# NodeJS-PGSQL-installer-script
This Script expects a freshly installed Debian|Ubuntu and Centos based machine.
##### Note: This Script runs in interactive mode and reads variable data from STDIN.
When run against privileged user it does the following things: 
- Create a system User
- Install NVM, Node and Angular/cli 
- Adds repo for Postgresql 
- Install Postgresql-server, start and enable it
- create a PSQL Role 
- Create a database and assign privileges to created role
