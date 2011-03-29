require 'helper'
require 'rake'

def rake_migrate
   Dir.chdir(Rails.root.join('.')) do
        Rake::Task['db:migrate'].execute
   end
end


class TestMigrationGenerator < Test::Unit::TestCase
  def run_against_template(template)
    assert_equal true, Migrant::MigrationGenerator.new.run, "Migration Generator reported an error"
    Dir.glob(File.join(File.dirname(__FILE__), 'rails_app', 'db' ,'migrate', '*.rb')).each do |migration_file|
        if migration_file.include?(template)
          to_test = File.open(migration_file, 'r') { |r| r.read}.strip
          File.open(File.join(File.dirname(__FILE__), 'verified_output', 'migrations', template+'.rb'), 'r') do |file|
            while (line = file.gets)
              assert_not_nil(to_test.match(line.strip), "Generated migration #{migration_file} missing line: #{line}")
            end
          end
          rake_migrate
          return
        end
    end
    flunk "No migration could be found"
  end

  context "The migration generator" do
    should "create migrations for all new tables" do
      assert_equal true, Migrant::MigrationGenerator.new.run, "Migration Generator reported an error"
      Dir.glob(File.join(File.dirname(__FILE__), 'rails_app', 'db' ,'migrate', '*.rb')).each do |migration_file|
         to_test = File.open(migration_file, 'r') { |r| r.read}.strip
         File.open(File.join(File.dirname(__FILE__), 'verified_output', 'migrations', migration_file.sub(/^.*\d+_/, '')), 'r') do |file|
           while (line = file.gets)
             assert_not_nil(to_test.match(line.strip), "Generated migration #{migration_file} missing line: #{line}")
           end
         end
      end
      rake_migrate
    end

    should "generate a migration for new added fields" do
      Business.structure do
        estimated_value 5000.0
        notes
      end
      run_against_template('estimated_value_notes')
    end

    should "generate a migration to alter existing columns where no data loss would occur" do
      Business.structure do
        landline :text
      end

      run_against_template('landline')
    end

    should "generate a migration to alter existing columns while adding a new table" do
      load File.join(File.dirname(__FILE__), 'additional_models', 'review.rb')
      User.belongs_to(:business) # To generate a business_id on a User
      User.no_structure # To force schema update

      run_against_template('create_reviews')
      run_against_template('business_id')
    end

    should "generate created_at and updated_at when given the column timestamps" do
      Business.structure do
        timestamps
      end
      run_against_template('created_at')
    end

    should "not change existing columns where data loss may occur" do
      Business.structure do
        landline :integer # Was previously a string, which obviously may incur data loss
      end
      assert_equal(false, Migrant::MigrationGenerator.new.run, "MigrationGenerator ran a dangerous migration!")
      Business.structure do
        landline :text # Undo our bad for the next tests
      end
    end

    should "exit immediately if there are pending migrations" do
     manual_migration = Rails.root.join("db/migrate/9999999999999999_my_new_migration.rb")
     File.open(manual_migration, 'w') { |f| f.write ' ' }
     assert_equal(false, Migrant::MigrationGenerator.new.run)
     File.delete(manual_migration)
    end

    should "still create sequential migrations for the folks not using timestamps" do
      Business.structure do
        new_field_i_made_up
      end
      # Remove migrations
      ActiveRecord::Base.timestamped_migrations = false
      assert_equal true, Migrant::MigrationGenerator.new.run, "Migration Generator reported an error"
      ActiveRecord::Base.timestamped_migrations = true

      assert_equal(Dir.glob(File.join(File.dirname(__FILE__), 'rails_app', 'db' ,'migrate', '*.rb')).select { |migration_file| migration_file.include?('new_field_i_made_up') }.length,
                   1,
                   "Migration should have been generated (without a duplicate)")
      rake_migrate                   
    end

    should "recursively generate mocks for every model" do
      BusinessCategory.structure do
        test_mockup_of_text :text
        test_mockup_of_string :string
        test_mockup_of_integer :integer
        test_mockup_of_float   :float
        test_mockup_of_datetime :datetime
        test_mockup_of_currency DataType::Currency
      end

      BusinessCategory.belongs_to(:notaclass, :polymorphic => true)
      assert_equal true, Migrant::MigrationGenerator.new.run, "Migration Generator reported an error"
      rake_migrate
      BusinessCategory.reset_column_information
      BusinessCategory.mock!
      mock = BusinessCategory.last
      assert_not_nil(mock)
      assert(mock.test_mockup_of_text.is_a?(String))
      assert(mock.test_mockup_of_string.is_a?(String))
      assert(mock.test_mockup_of_integer.is_a?(Fixnum))
      assert(mock.test_mockup_of_float.is_a?(Float))
      assert(mock.test_mockup_of_currency.is_a?(BigDecimal))    
      assert(mock.test_mockup_of_datetime.is_a?(Time))    
      assert(DataType::Base.default_mock.is_a?(String))
    end
        
    should "generate example mocks for an inherited model when STI is in effect" do
      assert_equal(5.00, Customer.mock.average_rating)
      assert_equal("somebody@somewhere.com", Customer.mock.email)
    end
    
    should "remove extraneous text from a filename too large for the operating system" do
      BusinessCategory.structure do
        a_very_very_long_field_indeed_far_too_long_for_any_good_use_really true
        a_very_very_long_field_indeed_far_too_long_for_any_good_use_really_2 true
        a_very_very_long_field_indeed_far_too_long_for_any_good_use_really_3 true
      end
      
      BusinessCategory.belongs_to(:verylongclassthatissuretogenerateaverylargeoutputfilename, :polymorphic => true)
      assert_equal true, Migrant::MigrationGenerator.new.run, "Migration Generator reported an error"
      rake_migrate
    end
  end
end

