---
layout: post
title: View models for Rails
description: 'Also known as decorators, presenters and view objects.'

---

There are a lot of great resources for learning about view models for Rails. They are also known as decorators, presenters and view objects. It is a solid concept that is easier said than done when implementing for the first time.

### Naming conventions

For this example, I've setup the following naming convention.

+ `app/view_models` - All of our view models will live here.
+ `<ViewModelName>View` - Add the suffix `View` to all classes.

All view models are composed of the model (or logic you are encaspulating) and the `view_context`.

{% highlight ruby %}
# app/views_models/product_view.rb
class ProductView
  def initialize(product, view_context)
    @product ||= product
    @v ||= view_context
  end
end
{% endhighlight %}

### View context

What is the `view_context` and where does it come from? The `view_context` is an instance of the Rails view class that will give us access to all of the helpers we might need to use such as `image_tag`, `content_tag` and url path helpers.

We have access to the `view_context` inside of controller actions.

{% highlight ruby %}
# app/controllers/store/products_controller.rb
module Store
  class ProductsController < StoreController
    def show
      # We have access to `view_context` here.
      product ||= Product.find_by(slug: params[:slug])
      @product_view ||= ProductView.new(product, view_context)
    end
  end
end
{% endhighlight %}

### Delegation

At this point our view model does not do anything. We do not have access to any of the product's attributes yet. We can use ActiveSupport `delegation` to delegate methods/atrributes to this view model.

{% highlight ruby %}
require 'active_support/core_ext/module/delegation'

class ProductView
  def initialize(product, view_context)
    @product ||= product
    @v ||= view_context
  end

  # Set attr_readers for initialized values.
  attr_reader :product, :v

  # Delegate methods/atrributes from `product`.
  delegate :name, to: :product
end
{% endhighlight %}

**Note:** Above we are only delegating the `:name` attribute, but you can delegate any method/attribute defined on product.

### View logic

Let's add some logic for determining the default image for a product.

{% highlight ruby %}
require 'active_support/core_ext/module/delegation'

class ProductView
  def initialize(product, view_context)
    @product ||= product
    @v ||= view_context
  end

  # Set attr_readers for initialized values.
  attr_reader :product, :v

  # Delegate methods/atrributes from `product`.
  delegate :name, to: :product

  # We use this image everywhere!
  def default_image(size = :thumbnail)
    product.image_url(size)
  end
end
{% endhighlight %}

And now let's add some more complex logic for displaying a price range.

{% highlight ruby %}
require 'active_support/core_ext/module/delegation'

class ProductView
  def initialize(product, view_context)
    @product ||= product
    @variants ||= product.variants
    @v ||= view_context
  end

  # Set attr_readers for initialized values.
  attr_reader :product, :variants, :v

  # Delegate methods/atrributes from `product`.
  delegate :name, to: :product

  # We use this image everywhere!
  def default_image(size = :thumbnail)
    product.image_url(size)
  end

  # Show min price or both prices if they are different.
  def price
    min, max = variants.map(&:unit_price).minmax
    output = v.number_to_currency(min)
    output = "#{output} - #{v.number_to_currency(max)}" if min != max
    output
  end
end
{% endhighlight %}

### Rendering collections and link references

Now we have a solid foundation to encasuplate any view related logic. However our view model is not ready yet.

+ Passing in a view model to `link_to` or `render` will result in an error.
+ How do we initialize a collection of view models?

These problems are easily solved by delegating some methods from our product model to our view model.

+ To enable `link_to` our view model needs to have `to_param` and `model_name` defined.
+ To enable `render @collection` our view model needs to have `to_partial_path` defined.
+ To initialize a collection of view models we define a class method to map over the passed in collection.

Our `Product` model inherits from `ActiveRecord::Base` which already defines these methods for us.

{% highlight ruby %}
require 'active_support/core_ext/module/delegation'

class ProductView
  def initialize(product, view_context)
    @product ||= product
    @variants ||= product.variants
    @v ||= view_context
  end

  # Set attr_readers for initialized values.
  attr_reader :product, :variants, :v

  # Delegate methods from `product`.
  delegate :name, to: :product

  # `link_to` expects passed in object to have `to_param` and `model_name` defined.
  # `render` expects passed in collection objects to have `to_partial_path` defined.
  # Our `Product` model inherits from ` ActiveRecord::Base` which already define these methods for us.
  delegate :to_param, :model_name, :to_partial_path to: :product

  # Initialize collection
  def self.collection(products, view_context)
    products.map { |p| self.new(p, view_context) }
  end

  # We use this image everywhere!
  def default_image(size = :thumbnail)
    product.image_url(size)
  end

  # Show min price or both prices if they are different.
  def price
    min, max = variants.map(&:unit_price).minmax
    output = v.number_to_currency(min)
    output = "#{output} - #{v.number_to_currency(max)}" if min != max
    output
  end
end
{% endhighlight %}

In our controller we setup our view model collection.

{% highlight ruby %}
module Store
  class ProductsController < StoreController
    def index
      # Pass in a collection of products to the `self.collection` method defined in our view model.
      products ||= Product.all.sorted.visible
      @products ||= ProductView.collection(products, view_context)
    end

    def show
      # We have access to `view_context` here.
      product ||= Product.find_by(slug: params[:slug])
      @product_view ||= ProductView.new(product, view_context)
    end
  end
end
{% endhighlight %}

And in our view we can call `render` and use `link_to` as expected.

{% highlight erb %}
<%= render @products %>
{% endhighlight %}

{% highlight erb %}
<%= link_to image_tag(product.default_image), store_product_path(product) %>
<p>
  <%= link_to product.name, store_product_path(product) %>
</p>
<p class="price">
  <%= product.price %>
</p>
{% endhighlight %}
