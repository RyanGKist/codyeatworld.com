---
layout: post
title: 'Rails: Uploading images confidently with Shrine.rb'
description: Upload images using Shrine.rb and Dropzone.js.
---

## Introduction

Shrine is file uploading library written in Ruby, it's compatible with plain ol' Ruby, Rails, Hanami, and any other Rack-based web framework.

You should use Shrine if you are starting a new project or want to upgrade your existing solution to use something more flexible than carrierwave, paperclip or refile. Shrine is a library for file uploading and provides tools to build plugins on top of. Because of this, almost all of Shrine's configuration is done through plugins.

### Security

A file upload form can easily become an attack vector. Shrine incorporates best practices and patterns for securely uploading files and images. [Janko Marohnić](https://github.com/janko-m) is the creator of Shrine and cares a lot of improving the current state of file uploading in Ruby. Check out his [blog](https://twin.github.io/) and the Shrine [documentation](http://shrinerb.com/) for more in depth knowledge about file uploading.

* * *

**Source code**: [https://github.com/codyeatworld/example-shrine-dropzone](https://github.com/codyeatworld/example-shrine-dropzone)

**Backgrounding**: [https://github.com/codyeatworld/example-shrine-dropzone/tree/backgrounding](https://github.com/codyeatworld/example-shrine-dropzone/tree/backgrounding)

**Live example**: [https://stark-falls-70810.herokuapp.com/](https://stark-falls-70810.herokuapp.com/)

* * *

## Shrine

To begin, let's out line what our requirements for image uploading are:

+ Upload images to Amazon S3
+ Image versioning (sm, mg, lg, etc...)
+ Ensure image files are cleaned up
+ Upload in background
+ Validate size and filetype
+ Remove attached image
+ Cache image file on errors
+ Drag and drop upload
+ Access images through CloudFront CDN

### Install

Our requirements are fairly modest, so lets start by installing the gems well need to use. Anytime you install a plugin with Shrine it's a good idea to read the full documenation for it to learn about usage and gem dependencies.

{% highlight ruby %}
# Upload images to Amazon S3
gem 'aws-sdk'
# Required for image versioning
gem 'image_processing'
# Required for image versioning
gem 'mini_magick'
# Shrine :)
gem 'shrine'
{% endhighlight %}

### Initializer

Next, lets create an initializer called `config/initializers/shrine.rb`. This file will be responsible for configurating plugins and background jobs.

{% highlight ruby %}
require 'shrine'
require 'shrine/storage/s3'

s3_options = {
  # Required
  region: ENV['aws_region'],
  bucket: ENV['aws_bucket'],
  access_key_id: ENV['aws_access_key_id'],
  secret_access_key: ENV['aws_secret_access_key']
}

# URL options for CloudFront CDN
url_options = {
  public: true,
  host: ENV['aws_host']
}

# The S3 storage plugin handles uploads to Amazon S3 service, using the aws-sdk gem.
Shrine.storages = {
  # With Shrine both temporary (:cache) and permanent (:store) storage are first-class citizens and fully configurable, so you can also have files cached on S3.
  cache: Shrine::Storage::S3.new(prefix: 'cache', upload_options: { acl: 'public-read' }, **s3_options),
  store: Shrine::Storage::S3.new(prefix: 'store', upload_options: { acl: 'public-read' }, **s3_options)
}

# Plugins

# Provides ActiveRecord integration, adding callbacks and validations.
Shrine.plugin :activerecord
# Automatically logs processing, storing and deleting, with a configurable format.
Shrine.plugin :logging, logger: Rails.logger
# Allows you to specify default URL options for uploaded files.
Shrine.plugin :default_url_options, cache: url_options, store: url_options

# Backgrounding

# Adds the ability to put storing and deleting into a background job.
Shrine.plugin :backgrounding

# Setup background jobs (sidekiq workers) for async uploads.
# app/jobs/shrine_backgrounding/promote_job.rb
Shrine::Attacher.promote { |data| ShrineBackgrounding::PromoteJob.perform_async(data) }
# app/jobs/shrine_backgrounding/delete_job.rb
Shrine::Attacher.delete { |data| ShrineBackgrounding::DeleteJob.perform_async(data) }
{% endhighlight %}

#### Background jobs

The backgrounding plugin exposes the promote and delete methods where we can pass a sidekiq worker. We define these workers in `app/jobs`.

Versioned files are processed in a promote job, if your sidekiq server is not running, then versioned images will not work. By default the original file will be used for a missing version until it becomes available.

You can use the plugin `:recache` to make some version available immediately and process others in the background.


{% highlight ruby %}
# app/jobs/shrine_backgrounding/delete_job.rb
module ShrineBackgrounding
  class DeleteJob
    include Sidekiq::Worker

    def perform(data)
      Shrine::Attacher.delete(data)
    end
  end
end

# app/jobs/shrine_backgrounding/promote_job.rb
module ShrineBackgrounding
  class PromoteJob
    include Sidekiq::Worker

    def perform(data)
      Shrine::Attacher.promote(data)
    end
  end
end
{% endhighlight %}

### Uploader

With the initializer setup we are ready to create an uploader class which inherits from `Shrine`. This uploader class will be responsible for encasuplating requirements for uploading files. For this example we will create a generic image uploader class that can be applied to most models.

{% highlight ruby %}
# MiniMagick
require 'image_processing/mini_magick'

class PictureUploader < Shrine
  # Use MiniMagick to process image versions
  include ImageProcessing::MiniMagick

  # The determine_mime_type plugin allows you to determine and store the actual MIME type of the file analyzed from file content.
  plugin :determine_mime_type
  # The remove_attachment plugin allows you to delete attachments through checkboxes on the web form.
  plugin :remove_attachment
  # The store_dimensions plugin extracts and stores dimensions of the uploaded image using the fastimage gem, which has built-in protection agains image bombs.
  plugin :store_dimensions
  # The validation_helpers plugin provides helper methods for validating attached files.
  plugin :validation_helpers
  # The pretty_location plugin attempts to generate a nicer folder structure for uploaded files.
  plugin :pretty_location
  # Allows you to define processing performed for a specific action.
  plugin :processing
  # The versions plugin enables your uploader to deal with versions, by allowing you to return a Hash of files when processing.
  plugin :versions
  # The delete_promoted plugin deletes files that have been promoted, after the record is saved. This means that cached files handled by the attacher will automatically get deleted once they're uploaded to store. This also applies to any other uploaded file passed to Attacher#promote.
  plugin :delete_promoted
  # The delete_raw plugin will automatically delete raw files that have been uploaded. This is especially useful when doing processing, to ensure that temporary files have been deleted after upload.
  plugin :delete_raw
  # The cached_attachment_data plugin adds the ability to retain the cached file across form redisplays, which means the file doesn't have to be reuploaded in case of validation errors.
  plugin :cached_attachment_data
  # The recache makes versions available immediately.
  plugin :recache
  

  # Define validations
  # For a complete list of all validation helpers, see AttacherMethods. http://shrinerb.com/rdoc/classes/Shrine/Plugins/ValidationHelpers/AttacherMethods.html
  Attacher.validate do
    validate_max_size 15.megabytes, message: 'is too large (max is 15 MB)'
    validate_mime_type_inclusion ['image/jpeg', 'image/png', 'image/gif']
  end


  # Access :original and :thumbnail versions immediately.
  # Recaching will be automatically triggered in a callback.
  process(:recache) do |io|
    {
      original: io,
      thumbnail: resize_to_fill!(io.download, 600, 600)
    }
  end
 
  # Process additional versions in background.
  process(:store) do |io|
    original = io[:original].download

    {
      # Original
      sm: resize_to_fit(original, 350, 350),
      md: resize_to_fit(original, 600, 600),
      lg: resize_to_fit(original, 1200, 1200),
 
      # Squares
      sm_square: resize_to_fill(original, 350, 350),
      md_square: resize_to_fill(original, 600, 600),
      lg_square: resize_to_fill(original, 1200, 1200),
    }
  end
end
{% endhighlight %}

This generic uploader seems to be doing a lot of work, but remember that Shrine is a library which encourages the use of plugins to drive its functionality. As of right now, we have a fairly lightweight uploader that fulfills all of our requirements.

* * *

## Dropzone

For any javascript based library I prefer to use `rails-assets` to keep up with updates and keep one less package manager out of the stack (bower, npm).

### Install

If you would like to use `rails-assets` to require Dropzone, then place the following block in your `Gemfile`.

{% highlight ruby %}
source 'https://rails-assets.org' do
  gem 'rails-assets-dropzone'
end
{% endhighlight %}

Or head over to dropzone.com for alternative installation solutions.

### JavaScript

Setting up Dropzone is fairly simple, we'll use data attributes to tell Dropzone what controller endpoint it should use. 

We will also need to pass in the `X-CSRF-Token` request header for Rails which we can grab from the meta tag. You can also use a skip action filter to disable it, but I prefer not to.

{% highlight javascript %}
Dropzone.autoDiscover = false;

$(function() {
  var pictureDropzone = new Dropzone('#picture_dropzone', {
    url: $('#picture_dropzone').data('url'),
    previewTemplate: $('#dropzone_preview_template').html(),
    previewsContainer: '#dropzone_previews_container',
    acceptedFiles: 'image/*',
    headers: {
      'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content')
    },
    maxFileSize: 15
  });

  pictureDropzone.on('success', function(file, response) {
    $('#pictures').append(response.picture);

    setTimeout(function() {
      pictureDropzone.removeFile(file)
    }, 3500);
  });
});
{% endhighlight %}

Out of habit/convention, I've named all the div's and id's after the model name (picture). We'll refer to the them in the view later.

* * *

## Rails

This next part will dive into the code required to make Shrine work inside a Rails environment and reuse partials inside the controller. 

Shrine's code is mostly reusable across different frameworks and projects. If you are interested in an Hanami example, let me know!


### Models

Shrine looks for a `<attribute>_data` column when an uploader is attached. Knowing this we can generate a model to attach an uploader to.


{% highlight bash %}
rails g model picture file_data
rails db:migrate
{% endhighlight %}

In our model, we pass in the `<attribute>` name when attaching the uploader.

{% highlight ruby %}
class Picture < ApplicationRecord
  include PictureUploader[:file]
end
{% endhighlight %}

### Routes

Lets define some routes to display and create pictures.

The `index` route will be display the uploaded image and provide a drag an drop interface to upload images.

The create action will be the endpoint for Dropzone. Dropzone will hit the endpoint for **each** file. So our `create` action can return the uploaded image.

{% highlight ruby %}
Rails.application.routes.draw do
  resources :pictures, only: [:index, :create]
  root 'pictures#index'
end
{% endhighlight %}

### Controllers

This is the meat of the entire uploader and it really shows how amazing it is work with Rails, Shrine and Dropzone all together. 

{% highlight ruby %}
class PicturesController < ApplicationController
  # skip_before_action :verify_authenticity_token, only: [:create]

  def index
    @pictures = Picture.sorted
  end

  def create
    # Dropzone will send each file inside of the `:file` param.
    @picture = Picture.create(file: params[:file])

    # Return a json response of the partial `_picture.html.erb` so Dropzone can append the uploaded image to the dom if the `@picture` object was successfully created.
    if @picture
      # Reuse existing partial
      picture_partial = render_to_string(
        'pictures/_picture',
        layout: false,
        formats: [:html],
        locals: { picture: @picture }
      )

      render json: { picture: picture_partial }, status: 200
    else
      render json: @picture.errors, status: 400
    end
  end

end
{% endhighlight %}

### Views

Just like with image uploader, let's outline our requirements for creating the view:

+ View all uploaded images in a grid.
+ A form/dropzone for uploading new images.
+ Automatically append uploaded images to the grid.

All we need to make this happen is one partial to render our picture. Let's begin by outlining the required HTML for `pictures/index.html.erb` which will render our partial.

{% highlight erb %}
<div class="container">
  <div id="picture_dropzone" class="card p-5 my-5" data-url="<%= pictures_path %>">
    <h4 class="text-center m-y-0">
      Drop files here or click to upload.
    </h4>
    <div class="fallback">
      <strong>Please enable javascript to upload images.</strong>
    </div>
    <div id="dropzone_previews_container"></div>
  </div>

  <div id="pictures" class="row">
    <%= render @pictures %>
  </div>
</div>

<div id="dropzone_preview_template" style="display: none;">
  <div class="dz-preview dz-file-preview">
    <div class="media mt-3">
      <img class="d-flex mr-3" data-dz-thumbnail height="75" width="75" />
      <div class="media-body">
        <h5 class="mt-0"><span data-dz-name></span></h5>
        <span class="text-muted">
          <span class="dz-size" data-dz-size></span>
        </span>
        <p class="dz-error-message text-danger">
          <span data-dz-errormessage></span>
        </p>
        <div class="progress">
          <div class="progress-bar progress-bar-striped progress-bar-animated" data-dz-uploadprogress></div>
        </div>
      </div>
    </div>
  </div>
</div>
{% endhighlight %}

This view is responsible for defining the div's for Dropzone to consume, and rendering the `@pictures` collection. I've also enabled a preview template for Dropzone to display while the image is uploading.

Next up is the `pictures/_picture` partial.

{% highlight erb %}
<%= content_tag :div, id: dom_id(picture), class: 'col-3' do %>
  <%= link_to image_tag(picture.file_url(:thumbnail), class: 'rounded img-fluid mb-4'), picture.file_url(:original) %>
<% end %>
{% endhighlight %}

With our picture partial in place, our uploader is now complete.

* * *

## Recap

Let's recap whats going on:

1. A user just dropped multiple files into the designated dropzone interface.
2. Dropzone hits the endpoint for each file the user dropped.
3. Rails created a new picture object, passing in the param from Dropzone.
4. Shrine automatically handles the data correctly.
5. If the picture object is created successfully then Rails renders the picture partial as an html string and return inside a JSON object.
6. When Dropzone receives a response back from Rails it reads the JSON object and appends the html string inside the DOM.

* * *

**Source code**: [https://github.com/codyeatworld/example-shrine-dropzone](https://github.com/codyeatworld/example-shrine-dropzone)

**Backgrounding**: [https://github.com/codyeatworld/example-shrine-dropzone/tree/backgrounding](https://github.com/codyeatworld/example-shrine-dropzone/tree/backgrounding)

**Live example**: [https://stark-falls-70810.herokuapp.com/](https://stark-falls-70810.herokuapp.com/)
