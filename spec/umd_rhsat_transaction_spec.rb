require 'spec_helper'
require 'umd/rhsat/transaction'

describe Umd::Rhsat::Transaction do
    it 'commits a sequence of subtransactions' do
        sequence = []

        Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(1)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(2)
                end
            end
        end.commit

        sequence.should eql([1, 2])
    end

    it 'rolls back a failed subtransaction' do
        sequence = []

        transaction = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(1)
                end

                on_rollback do
                    sequence.delete(1)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(2)
                end

                on_rollback do
                    sequence.delete(2)
                end
            end

            subtransaction do
                on_commit do
                    raise 'failure'
                end
            end
        end

        expect { transaction.commit }.to raise_error(/failure/)
        sequence.should eql([])
    end

    it 'commits a nested sequence of subtransactions' do
        sequence = []

        t1 = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(1)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(2)
                end
            end
        end

        t2 = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(3)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(4)
                end
            end
        end

        Umd::Rhsat::Transaction.new do
            subtransaction t1
            subtransaction t2
        end.commit

        sequence.should eql([1, 2, 3, 4])
    end
    
    it 'rolls back a nested sequence of subtransactions' do
        sequence = []

        t1 = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(1)
                end

                on_rollback do
                    sequence.delete(1)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(2)
                end

                on_rollback do
                    sequence.delete(2)
                end
            end
        end

        t2 = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(3)
                end

                on_rollback do
                    sequence.delete(3)
                end
            end

            subtransaction do
                on_commit do
                    raise 'failure'
                end
            end
        end

        transaction = Umd::Rhsat::Transaction.new do
            subtransaction t1
            subtransaction t2
        end

        expect { transaction.commit }.to raise_error(/failure/)
        sequence.should eql([])
    end
    
    it 'stops rolling back when a rollback callback fails' do
        sequence = []

        transaction = Umd::Rhsat::Transaction.new do
            subtransaction do
                on_commit do
                    sequence.push(1)
                end

                on_rollback do
                    sequence.delete(1)
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(2)
                end

                on_rollback do
                    raise 'failed rollback'
                end
            end

            subtransaction do
                on_commit do
                    sequence.push(3)
                end

                on_rollback do
                    sequence.delete(3)
                end
            end

            subtransaction do
                on_commit do
                    raise 'failed commit'
                end
            end
        end

        expect { transaction.commit }.to raise_error(/failed commit.*failed rollback/)
        sequence.should eql([1, 2])
    end

    describe 'undoing transactions' do
        def create_transaction(sequence)
            t1 = Umd::Rhsat::Transaction.new do
                subtransaction do
                    on_rollback do
                        sequence.push(1)
                    end
                end

                subtransaction do
                    on_rollback do
                        sequence.push(2)
                    end
                end
            end

            t2 = Umd::Rhsat::Transaction.new do
                subtransaction do
                    on_rollback do
                        sequence.push(3)
                    end
                end

                subtransaction do
                    on_rollback do
                        sequence.push(4)
                    end
                end
            end

            Umd::Rhsat::Transaction.new do
                subtransaction t1
                subtransaction t2
            end
        end
    
        it 'can be done by inversion' do
            sequence = []
            create_transaction(sequence).invert.commit
            sequence.should eql([4, 3, 2, 1])
        end

        it 'can be done by rollback' do
            sequence = []
            create_transaction(sequence).invert.commit
            sequence.should eql([4, 3, 2, 1])
        end
    end
end
