#!/bin/bash

# This script sets up the environment for the project.

# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"
# Install node.js
nvm install 22


#verify installation
node -v
npm -v


#install mysql
sudo apt-get update
sudo apt-get install mysql-server -y 

# Set MySQL root password
sudo mysql
# Enter the MySQL shell and run the following commands
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'Aditya';
FLUSH PRIVILEGES;
EXIT;

# Create user with privileges
sudo mysql -u root -p <<EOF
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EXIT;
EOF






# Create tables
sudo mysql -u $DB_USER -p$DB_PASSWORD -h $DB_HOST $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (product_id) REFERENCES products(id)
);
EOF

# install dependencies
npm install
# Start the project
npm start
# End

kubectl get ingress -n prod
nslookup url