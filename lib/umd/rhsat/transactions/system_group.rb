require 'umd/rhsat/transaction'
require 'umd/rhsat/transactions'
require 'umd/rhsat/transactions/activation_key'

# Transactions for managing system groups
#
# @author James T. Lee <jtl@umd.edu>
module Umd::Rhsat::Transactions::SystemGroup
    # Generate a transaction to create a system group and its associated
    # activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group to create
    # @param properties [Hash{String => Object}] properties to store in the system group's description field
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.create(server, name, properties)
        Umd::Rhsat::Transaction.new do |t|
            # create the system group
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#create
                    systemgroup = server.call('systemgroup.create', name, '{}')
                    server.set_system_group_properties(name, properties)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#delete
                    server.call('systemgroup.delete', name)
                end
            end)

            # create the activation key
            t.add_subtransaction(Umd::Rhsat::Transactions::ActivationKey.create(server, name, properties['activation_key']))

            # enable the system group
            t.add_subtransaction(enable(server, name))
        end
    end

    # Generate a transaction to delete a system group and its associated
    # activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group to delete
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.delete(server, name)
        create(server, name, server.get_system_group_properties(name)).invert
    end

    # Generate a transaction to disable a system group and its associated
    # activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group to disable
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.disable(server, name)
        Umd::Rhsat::Transaction.new do |t|
            # remove users from group
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    properties = server.get_system_group_properties(name)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#listUsers
                    all_users = server.call('user.listUsers').collect { |user| user['login'] }

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveAdmins)
                    server.call('systemgroup.addOrRemoveAdmins', name, properties['admins'] & all_users, 0)
                end

                st.on_rollback do
                    properties = server.get_system_group_properties(name)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/UserHandler.html#listUsers
                    all_users = server.call('user.listUsers').collect { |user| user['login'] }

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveAdmins
                    server.call('systemgroup.addOrRemoveAdmins', name, properties['admins'] & all_users, 1)
                end
            end)

            # disable activation key
            t.add_subtransaction(Umd::Rhsat::Transactions::ActivationKey.disable(server, name))

            # mark group as disabled
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    server.set_system_group_properties(name, 'enabled' => false)
                end

                st.on_rollback do
                    server.set_system_group_properties(name, 'enabled' => true)
                end
            end)
        end
    end

    # Generate a transaction to enable a system group and its associated
    # activation key.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group to enable
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.enable(server, name)
        disable(server, name).invert
    end

    # Wraps a transaction that renames a system group in another transaction
    # that preserves the list of systems assigned to the group
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param old_name [String] the old system group name
    # @param new_name [String] the new system group name
    # @param rename_transaction [Umd::Rhsat::Transaction] a transaction that renames the system group from <tt>old_name</tt> to <tt>new_name</tt>
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.preserve_and_rename(server, old_name, new_name, rename_transaction)
        # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#listSystems
        system_ids = server.call('systemgroup.listSystems', old_name).collect { |system| system['id'] }
        
        Umd::Rhsat::Transaction.new do |t|
            # remove systems from old system group
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveSystems
                    server.call('systemgroup.addOrRemoveSystems', old_name, system_ids, false)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveSystems
                    server.call('systemgroup.addOrRemoveSystems', old_name, system_ids, true)
                end
            end)

            # do the rename
            t.add_subtransaction(rename_transaction)

            # add systems into new system group
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveSystems
                    server.call('systemgroup.addOrRemoveSystems', new_name, system_ids, true)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#addOrRemoveSystems
                    server.call('systemgroup.addOrRemoveSystems', new_name, system_ids, false)
                end
            end)
        end
    end

    # Generate a transaction to change a system group's name.  It does
    # this by deleting the old system group and creating a new one.  It
    # preserves the list of systems assigned to the system group, and 
    # other properties like description and admins.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param old_name [String] the old system group name
    # @param new_name [String] the new system group name
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.rename(server, old_name, new_name)
        preserve_and_rename(server, old_name, new_name, Umd::Rhsat::Transaction.new do |t|
            # delete old system group
            t.add_subtransaction(delete(server, old_name))

            # create new system group
            t.add_subtransaction(create(server, new_name, server.get_system_group_properties(old_name)))
        end)
    end
end
