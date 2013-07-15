require 'umd/rhsat/transaction'
require 'xmlrpc/client'
require 'logging'

class Umd::Rhsat::Server
    # @param host [String] the hostname of the Red Hat Network Satellite server
    # @param path [String] the path to the XML-RPC endpoint, like '/xml/rpc'
    # @param (see #login)
    def initialize(host, path, username, password)
        @log = Logging.logger[self]
        @client = XMLRPC::Client.new(host, path)
        login(username, password)
    end

    # Start an API session with the Red Hat Network Satellite server
    #
    # @param username [String] the name of an existing privileged user
    # @param password [String] the password for the user
    # @raise [XMLRPC::FaultException]
    #   if an API failure is returned from the server
    def login(username, password)
        logout if @session

        # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/AuthHandler.html#login
        @session = @client.call('auth.login', username, password)
    end

    # End an API session with the Red Hat Network Satellite server
    #
    # @raise (see #login)
    def logout
        # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/AuthHandler.html#logout
        call('auth.logout')
        @session = nil
    end

    # Creates a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to create
    #   like 'jtl@umd.edu'
    # @param first_name [String] the user's first name
    # @param last_name [String] the user's last name
    # @param email [String] the user's email address
    # @param activation_key [String] an activation key in the format /^1-\\w+$/
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def create_user(username, first_name, last_name, email, activation_key)
        create_user_transaction(username, first_name, last_name, email, activation_key).commit
    end

    # Generate a transaction to create a user and its associated system
    # group and activation key.
    #
    # @param (see #create_user)
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    # @api private
    def create_user_transaction(username, first_name, last_name, email, activation_key)
        Umd::Rhsat::Transaction.new do |t|
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#create
                    systemgroup = call('systemgroup.create', username, activation_key)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#delete
                    call('systemgroup.delete', username)
                end
            end)

            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#create
                    call('activationkey.create', activation_key.split('-', 2)[1], username, '', [], false)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#delete
                    call('activationkey.delete', activation_key)
                end
            end)

            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    systemgroup = call('systemgroup.getDetails', username)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#addServerGroup
                    call('activationkey.addServerGroups', activation_key, [systemgroup['id']])
                end

                st.on_rollback do
                    systemgroup = call('systemgroup.getDetails', username)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#removeServerGroups
                    call('activationkey.removeServerGroups', activation_key, [systemgroup['id']])
                end
            end)

            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#create
                    call('user.create', username, '', first_name, last_name, email, 1)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#delete
                    call('user.delete', username)
                end
            end)
            
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#addAssignedSystemGroup
                    call('user.addAssignedSystemGroup', username, username, true)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#removeAssignedSystemGroup
                    call('user.removeAssignedSystemGroup', username, username, true)
                end
            end)
        end
    end

    # Deletes a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to delete
    #   like 'jtl@umd.edu'
    # @raise (see #create_user)
    # @todo Determine whether to delete systems too
    def delete_user(username)
        delete_user_transaction(username).commit
    end

    # Generate a transaction to remove a user and its associated system
    # group and activation key.
    #
    # @param (see #delete_user)
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    # @todo Determine whether to delete systems too
    # @api private
    def delete_user_transaction(username)
        user = call('user.getDetails', username)
        systemgroup = call('systemgroup.getDetails', username)
        create_user_transaction(username, user['first_name'], user['last_name'], user['email_address'], systemgroup['description']).invert
    end

    # Disable a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to disable
    #   like 'jtl@umd.edu'
    # @raise (see #create_user)
    def disable_user(username)
        disable_user_transaction(username).commit
    end

    # Generate a transaction to disable a user and its associated system
    # group and activation key.
    #
    # @param (see #disable_user)
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    # @api private
    def disable_user_transaction(username)
        Umd::Rhsat::Transaction.new do |t|
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#disable
                    call('user.disable', username)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#enable
                    call('user.enable', username)
                end
            end)

            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    systemgroup = call('systemgroup.getDetails', username)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#setDetails
                    call('activationkey.setDetails', systemgroup['description'], {'disabled' => true})
                end

                st.on_rollback do
                    systemgroup = call('systemgroup.getDetails', username)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#setDetails
                    call('activationkey.setDetails', systemgroup['description'], {'disabled' => false})
                end
            end)
        end
    end

    # Enable a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to enable
    #   like 'jtl@umd.edu'
    # @raise (see #create_user)
    def enable_user(username)
        enable_user_transaction(username).commit
    end

    # Generate a transaction to enable a user and its associated system
    # group and activation key.
    #
    # @param (see #disable_user)
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    # @api private
    def enable_user_transaction(username)
        disable_user_transaction(username).invert
    end

    # Wraps XML-RPC call to add the session key
    #
    # @param method [String] the XML-RPC method to call
    # @param args the arguments to pass to the XML-RPC method
    # @raise [RuntimeError] if not logged in
    # @raise (see #login)
    # @see https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/index.html Red Hat Network Satellite API Documentation
    def call(method, *args)
        raise 'not logged in' unless @session
        @log.debug "calling #{method} #{args}"
        @client.call(method, @session, *args)
    end
end
