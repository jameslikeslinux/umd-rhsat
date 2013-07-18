require 'umd/rhsat/transaction'
require 'umd/rhsat/transactions'

# Transactions for managing activation keys
#
# @author James T. Lee <jtl@umd.edu>
module Umd::Rhsat::Transactions::ActivationKey
    # Generate a transaction to create an activation key.  This assumes
    # that the corresponding system group exists.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group/activation key
    # @param activation_key [String] an activation key in the format /^1-\\w+$/
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.create(server, name, activation_key)
        Umd::Rhsat::Transaction.new do |t|
            # create the activation key
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#create
                    server.call('activationkey.create', activation_key.split('-', 2)[1], name, '', [], false)
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#delete
                    server.call('activationkey.delete', activation_key)
                end
            end)

            # add the system group to the key
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#getDetails
                    systemgroup = server.call('systemgroup.getDetails', name)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#addServerGroup
                    server.call('activationkey.addServerGroups', activation_key, [systemgroup['id']])
                end

                st.on_rollback do
                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ServerGroupHandler.html#getDetails
                    systemgroup = server.call('systemgroup.getDetails', name)

                    # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#removeServerGroups
                    server.call('activationkey.removeServerGroups', activation_key, [systemgroup['id']])
                end
            end)

            # add the activation key to the system group's description
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    server.set_system_group_properties(name, 'activation_key' => activation_key)
                end

                st.on_rollback do
                    server.set_system_group_properties(name, 'activation_key' => 'none')
                end
            end)
        end
    end

    # Generate a transaction to delete an activation key.  This assumes
    # that the corresponding system group exists.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group/activation key
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.delete(server, name)
        create(server, name, server.get_activation_key(name)).invert
    end

    # Generate a transaction to disable an activation key.  This assumes
    # that the corresponding system group exists.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group/activation key
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.disable(server, name)
        Umd::Rhsat::Transaction.new do |t| 
            t.on_commit do
                # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#setDetails
                server.call('activationkey.setDetails', server.get_activation_key(name), {'disabled' => true})
            end

            t.on_rollback do
                # https://access.redhat.com/site/documentation/en-US/Red_Hat_Network_Satellite/5.5/html/API_Overview/files/html/handlers/ActivationKeyHandler.html#setDetails
                server.call('activationkey.setDetails', server.get_activation_key(name), {'disabled' => false})
            end
        end
    end

    # Generate a transaction to enable an activation key.  This assumes
    # that the corresponding system group exists.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group/activation key
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.enable(server, name)
        disable(server, name).invert
    end

    # Generate a transaction to change an activation key.  It does this by
    # deleting the old activation key and creating a new one.  This assumes
    # that the corresponding system group exists.
    #
    # @param server [Umd::Rhsat::Server] the Satellite on which to operate
    # @param name [String] the name of the system group/activation key
    # @param new_activation_key [String] an activation key in the format /^1-\\w+$/
    # @return [Umd::Rhsat::Transaction] the initialized transaction
    def self.change(server, name, new_activation_key)
        Umd::Rhsat::Transaction.new do |t|
            t.add_subtransaction(delete(server, name))
            t.add_subtransaction(create(server, name, new_activation_key))
        end
    end
end
