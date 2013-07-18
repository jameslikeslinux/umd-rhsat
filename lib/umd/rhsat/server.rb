require 'json'
require 'logging'
require 'umd/rhsat'
require 'umd/rhsat/transactions/activation_key'
require 'umd/rhsat/transactions/system_group'
require 'umd/rhsat/transactions/user'
require 'xmlrpc/client'

# Connect to and perform API calls against a Red Hat Network Satellite
# server.  Provides methods to manage users, system groups, and
# activation keys in a transaction-safe manner.
#
# @example
#   server = Umd::Rhsat::Server.new('rhsat.example.com', '/rpc/api', 'foouser', 'password')
#   server.create_user('anewuser', 'First', 'Last', 'anewuser@example.com', '1-anewactivationkey')
#   server.call('user.listUsers')   # call arbirtary API methods
#   server.logout
#
# @see https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/index.html RHN Satellite API Documentation
# @author James T. Lee <jtl@umd.edu>
#
# @!attribute host [r] The hostname of the Red Hat Network Satellite server
# @!attribute path [r] The path to the XML-RPC endpoint, like '/rpc/api'
# @!attribute username [r] The username used to log in to the server
class Umd::Rhsat::Server
    attr_reader :host, :path, :username

    # @param host [String] the hostname of the Red Hat Network Satellite server
    # @param path [String] the path to the XML-RPC endpoint, like '/rpc/api'
    # @param username [String] the name of an existing privileged user
    # @param password [String] the password for the user
    def initialize(host, path, username, password)
        @log = Logging.logger[self]
        @host = host
        @path = path
        @username = username
        @password = password
        @client = XMLRPC::Client.new(host, path)
        login
    end

    # Start an API session with the Red Hat Network Satellite server
    #
    # @raise [XMLRPC::FaultException]
    #   if an API failure is returned from the server
    def login
        logout if @session

        # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/AuthHandler.html#login
        @session = @client.call('auth.login', @username, @password)
    end

    # End an API session with the Red Hat Network Satellite server
    #
    # @raise (see #call)
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
        Umd::Rhsat::Transactions::User.create(self, username, first_name, last_name, email, activation_key).commit
    end

    # Deletes a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to delete
    #   like 'jtl@umd.edu'
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    # @todo Determine whether to delete systems too
    def delete_user(username)
        Umd::Rhsat::Transactions::User.delete(self, username).commit
    end

    # Disable a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to disable
    #   like 'jtl@umd.edu'
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def disable_user(username)
        Umd::Rhsat::Transactions::User.disable(self, username).commit
    end

    # Enable a user and its associated system group and activation key.
    #
    # @param username [String] the username of the user to enable
    #   like 'jtl@umd.edu'
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def enable_user(username)
        Umd::Rhsat::Transactions::User.enable(self, username).commit
    end

    # Renames a user and its associated system group and activation key.
    #
    # @param old_username [String] the old username
    # @param new_username [String] the new username
    # @param new_email [String] the user's new email address
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def rename_user(old_username, new_username, new_email)
        Umd::Rhsat::Transactions::User.rename(self, old_username, new_username, new_email).commit
    end

    # Create a system group and its associated activation key, and
    # assign admins to the group.
    #
    # @param name [String] the name of the system group to create
    # @param description [String] a description to give to the system group
    # @param activation_key [String] an activation key in the format /^1-\\w+$/
    # @param admins [Array<String>] a list of users who can view and manage the system group
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def create_system_group(name, description, activation_key, admins)
        Umd::Rhsat::Transactions::SystemGroup.create(self, name, 'description' => description, 'activation_key' => activation_key, 'admins' => admins, 'default' => false).commit
    end

    # Delete a system group and its associated activation key.
    #
    # @param name [String] the name of the system group to delete
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def delete_system_group(name)
        Umd::Rhsat::Transactions::SystemGroup.delete(self, name).commit
    end

    # Disable a system group and its associated activation key.
    #
    # @param name [String] the name of the system group to disable
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def disable_system_group(name)
        Umd::Rhsat::Transactions::SystemGroup.disable(self, name).commit
    end

    # Enable a system group and its associated activation key.
    #
    # @param name [String] the name of the system group to enable
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def enable_system_group(name)
        Umd::Rhsat::Transactions::SystemGroup.enable(self, name).commit
    end

    # Change a system group's name.  It does this by deleting the old
    # system group and creating a new one.  It preserves the list of
    # systems assigned to the system group, and other properties like
    # description and admins.
    #
    # @param old_name [String] the old system group name
    # @param new_name [String] the new system group name
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def rename_system_group(old_name, new_name)
        Umd::Rhsat::Transactions::SystemGroup.rename(self, old_name, new_name).commit
    end

    # Change a system group's properties
    #
    # @param name [String] the name of the system group
    # @param description [String] a description to give to the system group
    # @param admins [Array<String>] a list of users who can view and manage the system group
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def change_system_group(name, description, admins)
        Umd::Rhsat::Transactions::SystemGroup.change(self, name, description, admins).commit
    end

    # Change an activation key.  It does this by deleting the old
    # activation key and creating a new one.  This assumes that the
    # corresponding system group exists.
    #
    # @param name [String] the name of the system group/activation key
    # @param new_activation_key [String] an activation key in the format /^1-\\w+$/
    # @raise [Umd::Rhsat::Transaction::TransactionError]
    #   if an API failure is returned from the server
    def change_activation_key(name, new_activation_key)
        Umd::Rhsat::Transactions::ActivationKey.change(self, name, new_activation_key).commit
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

    # Get properties stored in the system group's description field
    #
    # @param name [String] the name of the system group
    # @return [Hash{String => Object}] the system group's properties
    def get_system_group_properties(name)
        systemgroup = call('systemgroup.getDetails', name)
        Umd::Rhsat::Server.unmarshal(systemgroup['description'])
    end

    # Set properties stored in the system group's description field.
    # New properites are merged with existing properties.
    #
    # @param name [String] the name of the system group
    # @param new_properties [Hash{String => Object}] properties to merge into the system group's properties
    def set_system_group_properties(name, new_properties)
        old_properties = get_system_group_properties(name)
        properties = old_properties.merge(new_properties)
        call('systemgroup.update', name, Umd::Rhsat::Server.marshal(properties))
    end

    # Get the activation key stored in the system group's properties
    #
    # @param system_group_name [String] the name of the system group
    # @return [String] the activation key for the system group
    def get_activation_key(system_group_name)
        get_system_group_properties(system_group_name)['activation_key']
    end

    # Convert a Hash to JSON for storage
    #
    # @param hash [Hash{String => Object}] the hash to marshal
    # @return [String] the JSON representation of <tt>hash</tt>
    # @api private
    def self.marshal(hash)
        JSON.pretty_generate(hash, :indent => '    ')
    end

    # Convert JSON to a Hash
    #
    # @param json [String] a JSON data structure
    # @return [Hash{String => Object}] the Hash representation of <tt>json</tt>
    # @api private
    def self.unmarshal(json)
        JSON.parse(json)
    end
end
