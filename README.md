
# Caput

**Caput** is a Ruby gem that helps you prepare a vanilla Ubuntu server to host one or more Rails applications. It automates the steps required to make an application ready for deployment with standard Capistrano commands.

**Note:** Caput does **not deploy the application itself**. Instead, it ensures that the server and the local repository are properly configured so that deployments can be done reliably with minimal manual steps.

Deploying Rails applications to a server can be surprisingly complex. While tools like Kamal provide a modern “official” deployment approach, they often require a public container registry and additional infrastructure that many teams do not want or need. On the other hand, Capistrano has been the tried-and-true method for decades, but its setup can be tedious, especially on a fresh Ubuntu server. This gem bridges the gap: it gives you a simple Capistrano-style workflow while preparing the server and the app environment, without requiring Passenger or complex container setups. Essentially, it automates the repetitive steps needed to make a Rails app server-ready, letting you focus on your app instead of manual server configuration.

---

## Installation

Add the gem to your Rails application's `Gemfile` in the development group:

```ruby
group :development do
  gem 'caput', '~> 0.1.0'
end
```

Or install it directly:

```bash
gem install caput
```

---

## Usage

### 1. Initialise

Run the following in the root folder of your Rails application:

```bash
caput init
```

This creates a `caput.conf` file containing configuration for your server and deployment settings.

### 2. Configure

Edit `caput.conf` with the correct values for your setup:

- `setup_user` — user on the server with sudo access  
- `deploy_user` — user that will own the app directories  
- `server` — hostname or IP of the server  
- `app_name` — short name for the Rails application  
- `hostname` — the hostname that will be used to access the app (DNS must resolve)

> Make sure MySQL and Nginx are installed on the server. Caput will notify you if these dependencies are missing.

If not already the case, update the config/database.yml file to use MySQL for storage instead of the default Sqlite3. The below section can be used as a template.

```production:
  primary: &production_primary
    adapter: mysql2
    encoding: utf8mb4
    database: <%= Rails.application.credentials.dig(:mysql, :database) %>
    username: <%= Rails.application.credentials.dig(:mysql, :username) %>
    password: <%= Rails.application.credentials.dig(:mysql, :password) %>
    host: localhost
    port: 3306
  cache:
    <<: *production_primary
  queue:
    <<: *production_primary
  cable:
    <<: *production_primary
```

The above also requires the database information is added to the Rails credentials file by running rails credentials:edit and adding a MySQL section.

```mysql:
  database: <DATABASE NAME>
  username: <DATABASE USERNAME>
  password: <DATABASE PASSWORD>
```

The database name is typically the application name suffixed with '_production'.

### 3. Prepare the server

Run:

```bash
caput server
```

Caput will:

- Validate prerequisites (MySQL client/server, Nginx, setup user, DNS) 
- Create the Capistrano-compatible folder structure 
- Set up a **systemd service** for Puma to serve requests in the background  
- Configure permissions for the `deploy` user  

> Caput does not deploy the Rails app. After this, you can deploy using standard Capistrano commands.

### 4. Configure the local repository

Run:

```bash
caput local
```

This will:

- Add Capistrano configuration and necessary files to your local Rails repository  
- Make the repository ready for deployments  

### 5. Deploy the application

Once the above has been performed, the application can be deployed using standard Capistrano commands.

```cap production deploy
```

---

## Notes

- Only a few prerequisites must be handled manually: MySQL, Nginx, setup user with sudo access, and DNS for the application hostname.  
- Caput is designed to allow hosting multiple Rails applications on the same server. Each application gets its own folder structure, systemd service, and Nginx configuration.

