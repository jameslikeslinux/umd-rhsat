require 'spec_helper'
require 'rhsat_config'
require 'umd/rhsat/server'

describe Umd::Rhsat::Server do
    it 'can connect to the server and log in' do
        server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
        server.logout
    end

    it 'can marshal and unmarshal data' do
        data = {'description' => 'this is a test', 'activation_key' => '1-12343248930257348248932', 'admins' => ['a', 'b', 'c']}
        Umd::Rhsat::Server.unmarshal(Umd::Rhsat::Server.marshal(data)).should eql(data)
    end

    describe 'users management' do
        before(:each) do
            @server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
        end

        after(:each) do
            ['testuser', 'newusername'].each do |username|
                begin
                    @server.delete_user(username)
                rescue
                    # do nothing
                end

                begin
                    @server.delete_system_group(username)
                rescue
                    # do nothing
                end
            end

            @server.logout
        end

        it 'handles transaction failures' do
            t = Umd::Rhsat::Transactions::User.create(@server, 'testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    raise 'foobar'
                end
            end)

            expect { t.commit }.to raise_error(/foobar/)

            # check that none of the expected resources got created
            expect { @server.call('systemgroup.getDetails', 'testuser') }.to raise_error(/Unable to locate or access server group/)
            expect { @server.call('activationkey.getDetails', '1-12345') }.to raise_error(/Could not find activation key/)
            expect { @server.call('user.getDetails', 'testuser') }.to raise_error(/No such user/)
        end

        it 'can delete users' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')

            # whether or not the user can be created successfully is a matter for another test

            @server.delete_user('testuser')

            # check that none of the expected resources got created
            expect { @server.call('systemgroup.getDetails', 'testuser') }.to raise_error(/Unable to locate or access server group/)
            expect { @server.call('activationkey.getDetails', '1-12345') }.to raise_error(/Could not find activation key/)
            expect { @server.call('user.getDetails', 'testuser') }.to raise_error(/No such user/)
        end

        it 'can create users' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')

            # check that the user's system group was created
            systemgroup = @server.call('systemgroup.getDetails', 'testuser')

            # check that the activation key exists and was assigned to only the above system group
            activationkey = @server.call('activationkey.getDetails', '1-12345')
            activationkey['server_group_ids'].should eql([systemgroup['id']])

            # check that the user exists and was assigned to only the above system group
            @server.call('user.listAssignedSystemGroups', 'testuser').should eql([systemgroup])
            @server.call('user.listDefaultSystemGroups', 'testuser').should eql([systemgroup])
        end

        it 'fails to create already existing user' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            expect { @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345') }.to raise_error(/Duplicate server group requested to be created/)
        end

        it 'fails to delete already deleted user' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.delete_user('testuser')
            expect { @server.delete_user('testuser') }.to raise_error(/No such user/)
        end

        it 'can disable users' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.disable_user('testuser')

            user = @server.call('user.getDetails', 'testuser')
            user['enabled'].should be_false

            activationkey = @server.call('activationkey.getDetails', '1-12345')
            activationkey['disabled'].should be_true
        end

        it 'can run disable many times' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.disable_user('testuser')
            @server.disable_user('testuser')
        end

        it 'can enable users' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.disable_user('testuser')

            # whether or not the user can be disabled successfully is a matter for another test

            @server.enable_user('testuser')
            
            user = @server.call('user.getDetails', 'testuser')
            user['enabled'].should be_true

            activationkey = @server.call('activationkey.getDetails', '1-12345')
            activationkey['disabled'].should be_false
        end

        it 'can run enable many times' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.disable_user('testuser')
            @server.enable_user('testuser')
            @server.enable_user('testuser')
        end

        it 'can handle rename failures' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            t = Umd::Rhsat::Transactions::User.rename(@server, 'testuser', 'newusername', 'newusername@foo.bar')
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    raise 'foobar'
                end
            end)

            expect { t.commit }.to raise_error(/foobar/)

            # the new username does not exist
            expect { @server.call('user.getDetails', 'newusername') }.to raise_error(/No such user/)

            # the old one does
            @server.call('user.getDetails', 'testuser')
        end

        it 'can rename users' do
            @server.create_user('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            @server.rename_user('testuser', 'newusername', 'newusername@foo.bar')

            # the old user is gone
            expect { @server.call('user.getDetails', 'testuser') }.to raise_error(/No such user/)

            # the new user is available
            user = @server.call('user.getDetails', 'newusername')
            user['first_name'].should eql('Test')
            user['last_name'].should eql('User')
            user['email'].should eql('newusername@foo.bar')

            # XXX: There should probably be more assertions here,
            # but considering the rename user builds on user creation and deletion
            # which is tested above, and we can't really test system management,
            # I am satisfied if the rename_user method doesn't raise any errors
        end
    end
    
    describe 'system group management' do
        before(:each) do
            @server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
            @server.create_user('testuser1', 'Test', 'User 1', 'testuser1@foo.bar', '1-abcde1')
            @server.create_user('testuser2', 'Test', 'User 2', 'testuser2@foo.bar', '1-abcde2')
            @server.create_user('testuser3', 'Test', 'User 3', 'testuser3@foo.bar', '1-abcde3')
        end

        after(:each) do
            ['testuser1', 'testuser2', 'testuser3', 'anonexistentuser'].each do |user|
                begin
                    @server.delete_user(user)
                rescue
                    # do nothing
                end
            end

            ['testgroup', 'newgroup'].each do |system_group| 
                begin
                    @server.delete_system_group(system_group)
                rescue
                    # do nothing
                end
            end

            @server.logout
        end

        it 'handles transaction failures' do
            t = Umd::Rhsat::Transactions::SystemGroup.create(@server, 'testgroup', 'description' => 'A Test System Group', 'activation_key' => '1-testgroup', 'admins' => ['testuser1', 'testuser2', 'anonexistentuser'], 'default' => false)
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    raise 'foobar'
                end
            end)

            expect { t.commit }.to raise_error(/foobar/)

            # check that none of the expected resources got created
            expect { @server.call('systemgroup.getDetails', 'testgroup') }.to raise_error(/Unable to locate or access server group/)
            expect { @server.call('activationkey.getDetails', '1-testgroup') }.to raise_error(/Could not find activation key/)
        end

        it 'can delete system groups' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])

            # whether or not this was created properly is a matter for another test

            @server.delete_system_group('testgroup')

            # check that none of the expected resources got created
            expect { @server.call('systemgroup.getDetails', 'testgroup') }.to raise_error(/Unable to locate or access server group/)
            expect { @server.call('activationkey.getDetails', '1-testgroup') }.to raise_error(/Could not find activation key/)
        end

        it 'can create system groups' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])

            # check that the system group was created
            systemgroup = @server.call('systemgroup.getDetails', 'testgroup')

            # check that the activation key exists and was assigned to only the above system group
            activationkey = @server.call('activationkey.getDetails', '1-testgroup')
            activationkey['server_group_ids'].should eql([systemgroup['id']])

            # check that the system group contains the right administrators
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser2')
            admins.should_not include('anonexistentuser')

            # check that the system group description field is being filled out properly
            @server.get_system_group_properties('testgroup').should eql({'description' => 'A Test System Group', 'activation_key' => '1-testgroup', 'admins' => ['testuser1', 'testuser2', 'anonexistentuser'], 'default' => false, 'enabled' => true})
        end

        it 'adds non-existent admins to system group when their user\'s are created' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser2')
            admins.should_not include('anonexistentuser')

            @server.create_user('anonexistentuser', 'Non', 'Existent', 'blah@foo.bar', '1-nonexistent')

            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser2', 'anonexistentuser')
        end

        it 'can disable system groups' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.disable_system_group('testgroup')

            # check that the group is described as disabled
            @server.get_system_group_properties('testgroup')['enabled'].should be_false

            # check that the group's activation key is disabled
            activationkey = @server.call('activationkey.getDetails', '1-testgroup')
            activationkey['disabled'].should be_true

            # check that the group doesn't have any admins assigned
            @server.call('systemgroup.listAdministrators', 'testgroup').collect { |admin| admin['login'] }.should_not include('testuser1', 'testuser2', 'anonexistentuser')
        end

        it 'can run disable many times' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.disable_system_group('testgroup')
            @server.disable_system_group('testgroup')
        end

        it 'can enable system groups' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.disable_system_group('testgroup')

            # whether or not the system group can be disabled successfully is a matter for another test
            
            @server.enable_system_group('testgroup')

            # check that the group is described as disabled
            @server.get_system_group_properties('testgroup')['enabled'].should be_true

            # check that the group's activation key is disabled
            activationkey = @server.call('activationkey.getDetails', '1-testgroup')
            activationkey['disabled'].should be_false

            # check that the system group contains the right administrators
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser2')
            admins.should_not include('anonexistentuser')
        end

        it 'can run enable many times' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.disable_system_group('testgroup')
            @server.enable_system_group('testgroup')
            @server.enable_system_group('testgroup')
        end

        it 'doesn\'t add users to disabled system groups until it is re-enabled' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.disable_system_group('testgroup')

            @server.create_user('anonexistentuser', 'Non', 'Existent', 'blah@foo.bar', '1-nonexistent')

            # check that the group doesn't have any admins assigned
            @server.call('systemgroup.listAdministrators', 'testgroup').collect { |admin| admin['login'] }.should_not include('testuser1', 'testuser2', 'anonexistentuser')

            @server.enable_system_group('testgroup')

            # confirm that the group has the previously non-existent user now that it is enabled
            @server.call('systemgroup.listAdministrators', 'testgroup').collect { |admin| admin['login'] }.should include('testuser1', 'testuser2', 'anonexistentuser')
        end

        it 'can handle rename failures' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            t = Umd::Rhsat::Transactions::SystemGroup.rename(@server, 'testgroup', 'newgroup')
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    raise 'foobar'
                end
            end)

            expect { t.commit }.to raise_error(/foobar/)

            # the new system group does not exist
            expect { @server.call('systemgroup.getDetails', 'newgroup') }.to raise_error(/Unable to locate or access server group/)

            # the old one does
            @server.call('systemgroup.getDetails', 'testgroup')
        end

        it 'can rename users' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.rename_system_group('testgroup', 'newgroup')

            # the old system group is gone
            expect { @server.call('systemgroup.getDetails', 'testgroup') }.to raise_error(/Unable to locate or access server group/)

            # the new system group is available
            @server.call('systemgroup.getDetails', 'newgroup')
            @server.get_system_group_properties('newgroup').should eql({'description' => 'A Test System Group', 'activation_key' => '1-testgroup', 'admins' => ['testuser1', 'testuser2', 'anonexistentuser'], 'default' => false, 'enabled' => true})
        end

        it 'can set and get system group properties' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.set_system_group_properties('testgroup', 'foo' => 'bar', 'description' => 'A New Description')
            @server.get_system_group_properties('testgroup').should eql({'description' => 'A New Description', 'activation_key' => '1-testgroup', 'admins' => ['testuser1', 'testuser2', 'anonexistentuser'], 'default' => false, 'enabled' => true, 'foo' => 'bar'})
        end

        it 'can change the description' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.change_system_group('testgroup', 'New System Group Name', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.get_system_group_properties('testgroup')['description'].should eql('New System Group Name')
        end

        it 'can add admins' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1'])
            @server.change_system_group('testgroup', 'A Test System Group', ['testuser1', 'testuser2', 'anonexistentuser'])

            # check that the description got updated
            @server.get_system_group_properties('testgroup')['admins'].should eql(['testuser1', 'testuser2', 'anonexistentuser'])

            # check that the group has the right admins 
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser2')
            admins.should_not include('anonexistentuser')
        end

        it 'can remove admins' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.change_system_group('testgroup', 'A Test System Group', ['testuser1'])

            # check that the description got updated
            @server.get_system_group_properties('testgroup')['admins'].should eql(['testuser1'])

            # check that the group has the right admins 
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1')
            admins.should_not include('testuser2', 'anonexistentuser')
        end

        it 'can add and remove admins at the same time' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.change_system_group('testgroup', 'A Test System Group', ['testuser1', 'testuser3'])

            # check that the description got updated
            @server.get_system_group_properties('testgroup')['admins'].should eql(['testuser1', 'testuser3'])

            # check that the group has the right admins 
            admins = @server.call('systemgroup.listAdministrators', 'testgroup').collect { |user| user['login'] }
            admins.should include('testuser1', 'testuser3')
            admins.should_not include('testuser2', 'anonexistentuser')
        end

        it 'can keep things exactly the same' do
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser1', 'testuser2', 'anonexistentuser'])
            @server.change_system_group('testgroup', 'A Test System Group', ['testuser1', 'testuser2', 'anonexistentuser'])
        end
    end
    
    describe 'activation key management' do
        before(:each) do
            @server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
            @server.create_system_group('testgroup', 'A Test System Group', '1-testgroup', ['testuser'])
        end

        after(:each) do
            begin
                @server.delete_system_group('testgroup')
            rescue
                # do nothing
            end

            # ensure we clean up any keys that were managed in the test
            ['1-testgroup', '1-anewkey'].each do |activation_key|
                begin
                    @server.call('activationkey.delete', activation_key)
                rescue
                    # do nothing
                end
            end

            @server.logout
        end

        it 'handles transaction failures' do
            t = Umd::Rhsat::Transactions::ActivationKey.change(@server, 'testgroup', '1-anewkey')
            t.add_subtransaction(Umd::Rhsat::Transaction.new do |st|
                st.on_commit do
                    raise 'foobar'
                end
            end)

            expect { t.commit }.to raise_error(/foobar/)

            # check that new system key doesn't exist
            expect { @server.call('activationkey.getDetails', '1-anewkey') }.to raise_error(/Could not find activation key/)

            # check that the old activation key exists and is assigned to its corresponding system group
            systemgroup = @server.call('systemgroup.getDetails', 'testgroup')
            activationkey = @server.call('activationkey.getDetails', '1-testgroup')
            activationkey['server_group_ids'].should eql([systemgroup['id']])

            # check that the old activation key is still set in the system group's description
            @server.get_activation_key('testgroup').should eql('1-testgroup')
        end

        it 'can change the activation key for a system group' do
            @server.change_activation_key('testgroup', '1-anewkey')

            # check that the old system key is gone
            expect { @server.call('activationkey.getDetails', '1-testgroup') }.to raise_error(/Could not find activation key/)

            # check that the new activation key exists and is assigned to its corresponding system group
            systemgroup = @server.call('systemgroup.getDetails', 'testgroup')
            activationkey = @server.call('activationkey.getDetails', '1-anewkey')
            activationkey['server_group_ids'].should eql([systemgroup['id']])

            # check that the new activation key is still set in the system group's description
            @server.get_activation_key('testgroup').should eql('1-anewkey')
        end
    end
end
