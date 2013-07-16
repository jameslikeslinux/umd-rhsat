require 'spec_helper'
require 'rhsat_config'
require 'umd/rhsat/server'

describe Umd::Rhsat::Server do
    it 'can connect to the server and log in' do
        server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
        server.logout
    end

    context 'users management' do
        before(:each) do
            @server = Umd::Rhsat::Server.new(RHSAT_HOST, RHSAT_PATH, RHSAT_USERNAME, RHSAT_PASSWORD)
        end

        after(:each) do
            begin
                @server.delete_user('testuser')
            rescue
                # do nothing
            end

            @server.logout
        end

        it 'can deal with transaction failures' do
            t1 = @server.create_user_transaction('testuser', 'Test', 'User', 'testuser@foo.bar', '1-12345')
            expect {
                Umd::Rhsat::Transaction.new do |t|
                    t.add_subtransaction(t1)
                    t.add_subtransaction(Umd::Rhsat::Transaction.new do |t2|
                        t2.on_commit do
                            raise 'foobar'
                        end
                    end)
                end.commit
            }.to raise_error(/foobar/)

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
    end
end
