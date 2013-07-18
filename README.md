# RHN Satellite Ruby Library #

This library currently implements an API interface to a Red Hat Network Satellite server.

## Usage ##

See {Umd::Rhsat::Server}.

## Contributing ##

1. Fork it: `git clone /cell_root/project/glue/r/ruby/modules/umd-rhsat/src/umd-rhsat.git && cd umd-rhsat`

2. Install dependencies: `bundle install --path $HOME/.gem`.  The gem uses
[Bundler](http://bundler.io/) to manage dependencies. If you've never worked
with gems in your home directory before, you'll probably have to add
`$HOME/.gem/ruby/<ruby_lib_version>/bin` to your path. 

3. Create your feature branch (`git checkout -b my-new-feature`).

4. Write tests and run them with:
`bundle exec rspec --format documentation spec`.
More importantly, make sure the tests pass.

5. Commit your changes (`git commit -a -m 'Add some feature'`).

6. Push the branch (`git push origin my-new-feature`).

7. Create a pull request.
