require 'umd/rhsat'
require 'umd/util/logging'

# This class implements a generic transaction model.  A transaction
# consists of a commit callback and a rollback callback.  Additionally,
# transactions can be nested.  If a commit callback raises a
# <tt>StandardError</tt>, then the rollback callbacks for all of the
# transactions committed before it will be rolled back.
#
# @example
#   Umd::Rhsat::Transaction.new do
#       subtransaction do
#           on_commit do
#               puts 'committing'
#           end
#
#           on_rollback do
#               puts 'rolling back'
#           end
#       end
#
#       subtransaction do
#           on_commit do
#               raise 'transaction failure'
#           end
#       end
#   end.commit
#
# @author James T. Lee <jtl@umd.edu>
class Umd::Rhsat::Transaction
    include Umd::Util::Logging

    # Since code is executed after errors in the commit phase
    # this error type is required to capture ary errors that might
    # occur during the rollback phase as well.
    #
    # @attr_reader commit_error [StandardError] the error that occurred during a commit, or nil
    # @attr_reader rollback_error [StandardError] the error that occurred during a rollback, or nil
    class TransactionError < StandardError
        attr_reader :commit_error, :rollback_error

        def initialize(commit_error = nil, rollback_error = nil)
            message = nil
            
            if commit_error and commit_error.message
                message = "commit failed with: #{commit_error.message}"
            end

            if rollback_error and rollback_error.message
                message += '; ' if message
                message += "rollback failed with: #{rollback_error.message}"
            end

            super(message)
            @commit_error = commit_error
            @rollback_error = rollback_error
        end
    end

   
    # @yield nothing 
    def initialize(&init)
        @commit_callback = nil
        @rollback_callback = nil
        @subtransactions = []

        instance_eval(&init)
    end    

    # Commit the transaction.  Subtransactions are iterated and executed
    # in order.  If the transaction has a commit block, it is called.
    # If it raises an error, the rollbacks of all preceding transactions
    # are called in reverse order.
    #
    # @raise [Umd::Rhsat::Transaction::TransactionError] if a commit or rollback step fails
    def commit
        if @commit_callback
            @commit_callback.call
        else
            completed_transactions = []
            @subtransactions.each do |t|
                begin
                    t.commit
                    completed_transactions.unshift(t)
                rescue => e
                    log.debug e

                    completed_transactions.each do |ct|
                        begin
                            ct.rollback
                        rescue => f
                            log.debug f
                            raise TransactionError.new(e, f)
                        end
                    end

                    raise TransactionError.new(e)
                end
            end
        end
    end

    # Allows a transaction to be undone unsafely
    # (which is to say, the rollback won't be rolled back if there
    # is a failure)
    #
    # @raise [Umd::Rhsat::Transaction::TransactionError] if a rollback step fails
    def rollback
        if @rollback_callback
            @rollback_callback.call
        else
            @subtransactions.reverse_each do |t|
                begin
                    t.rollback
                rescue => e
                    log.debug e
                    raise TransactionError.new(nil, e)
                end
            end
        end
    end

    # Set code to be executed during the transaction commit.
    # If this is set, then the transaction will execute it and not
    # any subtransactions.
    #
    # @yield nothing
    def on_commit(&code)
        @commit_callback = code
    end

    # Set code to be executed during the transaction rollback.
    # If this is set, then the transaction will execute it and not
    # any subtransactions.
    #
    # @yield nothing
    def on_rollback(&code)
        @rollback_callback = code
    end

    # Add a subtransaction to be executed.  Subtransactions are
    # executed in the order that they are added.  If code is set
    # with #on_commit or #on_rollback, then these will not be
    # considered.
    #
    # @example creating a new subtransaction with a block
    #   Umd::Rhsat::Transaction.new do
    #       subtransaction do
    #           on_commit do
    #               puts 'foo'
    #           end
    #       end
    #   end
    #
    # @example creating a new subtransaction by parameter  
    #   t = Umd::Rhsat::Transaction.new do
    #       on_commit do
    #           puts 'foo'
    #       end
    #   end
    #
    #   Umd::Rhsat::Transaction.new do
    #       subtransaction t
    #   end
    #
    # @param t [Umd::Rhsat::Transaction] a subtransaction, or nil initialize a new transaction from a block
    # @yield nothing
    def subtransaction(t = nil, &init)
        if t
            @subtransactions.push(t)
        else
            @subtransactions.push(Umd::Rhsat::Transaction.new(&init))
        end
    end

    # Allows a transaction to be undone safely
    #
    # @example can be chained like
    #   transaction.invert.commit
    # @return [Umd::Rhsat::Transaction] self
    def invert
        @subtransactions.reverse!

        tmp = @commit_callback
        @commit_callback = @rollback_callback
        @rollback_callback = tmp

        @subtransactions.each do |t|
            t.invert
        end

        self
    end
end
