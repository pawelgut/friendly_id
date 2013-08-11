# encoding: utf-8
require "friendly_id/slug_generator"
require "friendly_id/candidates"

module FriendlyId
=begin

## Slugged Models

FriendlyId can use a separate column to store slugs for models which require
some text processing.

For example, blog applications typically use a post title to provide the basis
of a search engine friendly URL. Such identifiers typically lack uppercase
characters, use ASCII to approximate UTF-8 character, and strip out other
characters which may make them aesthetically unappealing or error-prone when
used in a URL.

    class Post < ActiveRecord::Base
      extend FriendlyId
      friendly_id :title, :use => :slugged
    end

    @post = Post.create(:title => "This is the first post!")
    @post.friendly_id   # returns "this-is-the-first-post"
    redirect_to @post   # the URL will be /posts/this-is-the-first-post

In general, use slugs by default unless you know for sure you don't need them.
To activate the slugging functionality, use the {FriendlyId::Slugged} module.

FriendlyId will generate slugs from a method or column that you specify, and
store them in a field in your model. By default, this field must be named
`:slug`, though you may change this using the
{FriendlyId::Slugged::Configuration#slug_column slug_column} configuration
option. You should add an index to this column, and in most cases, make it
unique. You may also wish to constrain it to NOT NULL, but this depends on your
app's behavior and requirements.

### Example Setup

    # your model
    class Post < ActiveRecord::Base
      extend FriendlyId
      friendly_id :title, :use => :slugged
      validates_presence_of :title, :slug, :body
    end

    # a migration
    class CreatePosts < ActiveRecord::Migration
      def self.up
        create_table :posts do |t|
          t.string :title, :null => false
          t.string :slug, :null => false
          t.text :body
        end

        add_index :posts, :slug, :unique => true
      end

      def self.down
        drop_table :posts
      end
    end

### Working With Slugs

#### Formatting

By default, FriendlyId uses Active Support's
[paramaterize](http://api.rubyonrails.org/classes/ActiveSupport/Inflector.html#method-i-parameterize)
method to create slugs. This method will intelligently replace spaces with
dashes, and Unicode Latin characters with ASCII approximations:

    movie = Movie.create! :title => "Der Preis fürs Überleben"
    movie.slug #=> "der-preis-furs-uberleben"

#### Column or Method?

FriendlyId always uses a method as the basis of the slug text - not a column. It
first glance, this may sound confusing, but remember that Active Record provides
methods for each column in a model's associated table, and that's what
FriendlyId uses.

Here's an example of a class that uses a custom method to generate the slug:

    class Person < ActiveRecord::Base
      friendly_id :name_and_location
      def name_and_location
        "#{name} from #{location}"
      end
    end

    bob = Person.create! :name => "Bob Smith", :location => "New York City"
    bob.friendly_id #=> "bob-smith-from-new-york-city"

FriendlyId refers to this internally as the "base" method.

#### Uniqueness

When you try to insert a record that would generate a duplicate friendly id,
FriendlyId will append a UUID to the generated slug to ensure uniqueness:

    car = Car.create :title => "Peugot 206"
    car2 = Car.create :title => "Peugot 206"

    car.friendly_id #=> "peugot-206"
    car2.friendly_id #=> "peugot-206-f9f3789a-daec-4156-af1d-fab81aa16ee5"

Previous versions of FriendlyId appended a numeric sequence a to make slugs
unique, but this was removed to simplify using FriendlyId in concurrent code.

#### Candidates

Since UUIDs are ugly, FriendlyId provides a "slug candidates" functionality to
let you specify alternate slugs to use in the event the one you want to use is
already taken. For example:

    class Restaurant < ActiveRecord::Base
      extend FriendlyId
      friendly_id :slug_candidates, use: :slugged

      # Try building a slug based on the following fields in
      # increasing order of specificity.
      def slug_candidates
        [
          :name,
          [:name, :city],
          [:name, :street, :city],
          [:name, :street_number, :street, :city]
        ]
      end
    end

    r1 = Restaurant.create! name: 'Plaza Diner', city: 'New Paltz'
    r2 = Restaurant.create! name: 'Plaza Diner', city: 'Kingston'

    r1.friendly_id  #=> 'plaza-diner'
    r2.friendly_id  #=> 'plaza-diner-kingston'

To use candidates, make your FriendlyId base method return an array. The
method need not be named `slug_candidates`; it can be anything you want. The
array may contain any combination of symbols, strings, procs or lambdas and
will be evaluated lazily and in order. If you include symbols, FriendlyId will
invoke a method on your model class with the same name. Strings will be
interpreted literally. Procs and lambdas will be called and their return values
used as the basis of the friendly id. If none of the candidates can generate a
unique slug, then FriendlyId will append a UUID to the first candidate as a
last resort.

#### Sequence Separator

By default, FriendlyId uses a dash to separate the slug from a sequence.

You can change this with the {FriendlyId::Slugged::Configuration#sequence_separator
sequence_separator} configuration option.

#### Providing Your Own Slug Processing Method

You can override {FriendlyId::Slugged#normalize_friendly_id} in your model for
total control over the slug format. It will be invoked for any generated slug,
whether for a single slug or for slug candidates.

#### Deciding When to Generate New Slugs

Previous versions of FriendlyId provided a method named
`should_generate_new_friendly_id?` which you could override to control when new
slugs were generated.

As of FriendlyId 5.0, slugs are only generated when the `slug` field is nil. If
you want a slug to be regenerated, you must explicity set the field to nil:

    restaurant.friendly_id # joes-diner
    restaurant.name = "The Plaza Diner"
    restaurant.save!
    restaurant.friendly_id # joes-diner
    restaurant.slug = nil
    restaurant.save!
    restaurant.friendly_id # the-plaza-diner


#### Locale-specific Transliterations

Active Support's `parameterize` uses
[transliterate](http://api.rubyonrails.org/classes/ActiveSupport/Inflector.html#method-i-transliterate),
which in turn can use I18n's transliteration rules to consider the current
locale when replacing Latin characters:

    # config/locales/de.yml
    de:
      i18n:
        transliterate:
          rule:
            ü: "ue"
            ö: "oe"
            etc...

    movie = Movie.create! :title => "Der Preis fürs Überleben"
    movie.slug #=> "der-preis-fuers-ueberleben"

This functionality was in fact taken from earlier versions of FriendlyId.

#### Gotchas: Common Problems

FriendlyId uses a before_validation callback to generate and set the slug. This
means that if you create two model instances before saving them, it's possible
they will generate the same slug, and the second save will fail.

This can happen in two fairly normal cases: the first, when a model using nested
attributes creates more than one record for a model that uses friendly_id. The
second, in concurrent code, either in threads or multiple processes.

To solve the nested attributes issue, I recommend simply avoiding them when
creating more than one nested record for a model that uses FriendlyId. See [this
Github issue](https://github.com/norman/friendly_id/issues/185) for discussion.

=end
  module Slugged

    # Sets up behavior and configuration options for FriendlyId's slugging
    # feature.
    def self.included(model_class)
      model_class.friendly_id_config.instance_eval do
        self.class.send :include, Configuration
        self.slug_generator_class     ||= SlugGenerator
        defaults[:slug_column]        ||= 'slug'
        defaults[:sequence_separator] ||= '-'
      end
      model_class.before_validation :set_slug
    end

    # Process the given value to make it suitable for use as a slug.
    #
    # This method is not intended to be invoked directly; FriendlyId uses it
    # internaly to process strings into slugs.
    #
    # However, if FriendlyId's default slug generation doesn't suite your needs,
    # you can override this method in your model class to control exactly how
    # slugs are generated.
    #
    # ### Example
    #
    #     class Person < ActiveRecord::Base
    #       friendly_id :name_and_location
    #
    #       def name_and_location
    #         "#{name} from #{location}"
    #       end
    #
    #       # Use default slug, but upper case and with underscores
    #       def normalize_friendly_id(string)
    #         super.upcase.gsub("-", "_")
    #       end
    #     end
    #
    #     bob = Person.create! :name => "Bob Smith", :location => "New York City"
    #     bob.friendly_id #=> "BOB_SMITH_FROM_NEW_YORK_CITY"
    #
    # ### More Resources
    #
    # You might want to look into Babosa[https://github.com/norman/babosa],
    # which is the slugging library used by FriendlyId prior to version 4, which
    # offers some specialized functionality missing from Active Support.
    #
    # @param [#to_s] value The value used as the basis of the slug.
    # @return The candidate slug text, without a sequence.
    def normalize_friendly_id(value)
      value.to_s.parameterize
    end

    # Whether to generate a new slug.
    #
    # You can override this method in your model if, for example, you only want
    # slugs to be generated once, and then never updated.
    def should_generate_new_friendly_id?
      send(friendly_id_config.slug_column).nil? && !send(friendly_id_config.base).nil?
    end

    def resolve_friendly_id_conflict(candidates)
      candidates.first + friendly_id_config.sequence_separator + SecureRandom.uuid
    end

    # Sets the slug.
    def set_slug(normalized_slug = nil)
      if should_generate_new_friendly_id?
        candidates = FriendlyId::Candidates.new(self, normalized_slug || send(friendly_id_config.base))
        slug = slug_generator.generate(candidates) || resolve_friendly_id_conflict(candidates)
        send "#{friendly_id_config.slug_column}=", slug
      end
    end
    private :set_slug

    def slug_generator
      friendly_id_config.slug_generator_class.new(self.class.base_class.unscoped.friendly)
    end
    private :slug_generator

    # This module adds the `:slug_column`, and `:sequence_separator`, and
    # `:slug_generator_class` configuration options to
    # {FriendlyId::Configuration FriendlyId::Configuration}.
    module Configuration
      attr_writer :slug_column, :sequence_separator
      attr_accessor :slug_generator_class

      # Makes FriendlyId use the slug column for querying.
      # @return String The slug column.
      def query_field
        slug_column
      end

      # The string used to separate a slug base from a numeric sequence.
      #
      # You can change the default separator by setting the
      # {FriendlyId::Slugged::Configuration#sequence_separator
      # sequence_separator} configuration option.
      # @return String The sequence separator string. Defaults to "`-`".
      def sequence_separator
        @sequence_separator or defaults[:sequence_separator]
      end

      # The column that will be used to store the generated slug.
      def slug_column
        @slug_column or defaults[:slug_column]
      end
    end
  end
end
