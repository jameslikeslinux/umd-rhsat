require 'umd/rhsat/server'
require 'umd/rhsat/transaction'
require 'umd/rhsat/transactions'
require 'umd/rhsat/transactions/system_group'

# Transactions for managing users
#
# @author James T. Lee <jtl@umd.edu>
module Umd::Rhsat::Transactions::User
    # Generate a transaction to create a user and its associated system
    # group and activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param username [String] the username of the user to create
    #   like 'jtl@umd.edu'
    # @param first_name [String] the user's first name
    # @param last_name [String] the user's last name
    # @param email [String] the user's email address
    # @param activation_key [String] an activation key in the format /^1-\\w+$/
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.create(server, username, first_name, last_name, email, activation_key)
        Umd::Rhsat::Transaction.new do
            # create the user's private system group
            subtransaction Umd::Rhsat::Transactions::SystemGroup.create(server, username, 'description' => "Private System Group for #{username}", 'activation_key' => activation_key, 'admins' => [username], 'default' => true)

            # create the user and add it to any system groups for which it is already configured to be an admin of
            subtransaction do
                on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#create
                    server.call('user.create', username, '', first_name, last_name, email, 1)
         
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#listAllGroups
                    systemgroups = server.call('systemgroup.listAllGroups')
                    systemgroups.each do |systemgroup|
                        properties = Umd::Rhsat::Server.unmarshal(systemgroup['description'])
                        if properties['admins'].include?(username) and properties['enabled']
                            # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#addAssignedSystemGroup
                            server.call('user.addAssignedSystemGroup', username, systemgroup['name'], properties['default'])
                        end
                    end
                end

                on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#delete
                    server.call('user.delete', username)
                end
            end
        end
    end

    # Generate a transaction to remove a user and its associated system
    # group and activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param username [String] the username of the user to delete
    #   like 'jtl@umd.edu'
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    # @todo Determine whether to delete systems too
    def self.delete(server, username)
        user = server.call('user.getDetails', username)
        create(server, username, user['first_name'], user['last_name'], user['email'], server.get_activation_key(username)).invert
    end
    
    # Generate a transaction to disable a user and its associated system
    # group and activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param username [String] the username of the user to disable
    #   like 'jtl@umd.edu'
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.disable(server, username)
        Umd::Rhsat::Transaction.new do
            # disable the user
            subtransaction do
                on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#disable
                    server.call('user.disable', username)
                end

                on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#enable
                    server.call('user.enable', username)
                end
            end

            # disable the user's system group and activation key
            subtransaction Umd::Rhsat::Transactions::SystemGroup.disable(server, username)
        end
    end

    # Generate a transaction to enable a user and its associated system
    # group and activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param username [String] the username of the user to enable
    #   like 'jtl@umd.edu'
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.enable(server, username)
        disable(server, username).invert
    end

    # Generate a transaction to change a user's username.  It does
    # this by deleting the old user and creating a new one.  It
    # preserves the list of systems assigned to the user's private
    # system group.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param old_username [String] the old username
    # @param new_username [String] the new username
    # @param new_email [String] the user's new email address
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.rename(server, old_username, new_username, new_email)
        user = server.call('user.getDetails', old_username)

        Umd::Rhsat::Transactions::SystemGroup.preserve_and_rename(server, old_username, new_username, Umd::Rhsat::Transaction.new do
            # delete old user
            subtransaction Umd::Rhsat::Transactions::User.delete(server, old_username)

            # create new user
            subtransaction Umd::Rhsat::Transactions::User.create(server, new_username, user['first_name'], user['last_name'], new_email, server.get_activation_key(old_username))
        end)
    end
end
