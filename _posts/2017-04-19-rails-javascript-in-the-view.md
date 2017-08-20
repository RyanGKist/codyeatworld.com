---
layout: post
title: 'Rails: JavaScript in the View'
description: 'Take advantage of provide and content_for to write JavaScript in the view.'
published: false
---

Sometimes in Rails you want to write some JavaScript for only one view, or maybe you need to pass at a lot of data from the view to this JavaScript. The asset pipeline can make this difficult to acheive, but there is a pattern emerging that works around the asset pipeline.

## JavaScript in the view

To start, place a `content_for?` block right below your `javascript_include_tag` tag in your application layout.

{% highlight erb %}
<%= javascript_include_tag 'application' %>

<%= yield(:page_scripts) if content_for?(:page_scripts) %>
{% endhighlight %}

This will allow us to inject a script from the view under the included javascript from the asset pipeline. Now with our `content_for?` block in place, lets use it.

In the view you need JavaScript in, placed the following code at the very top.

{% highlight erb %}
<% provide :page_scripts do %>
  <script>
    console.log('Hello from the view.')
  </script>
<% end %>
{% endhighlight %}

If you want to keep this JS in a partial, you can inline the provide call.

{% highlight erb %}
<% provide :page_scripts, render('hello.js') %>
{% endhighlight %}

You will need to wrap a `script` block around the code in either the application layout or partial.

## Realtime data

While this solution works great for certain situations, more often than not, you'll want that data to be updating in realtime.

Let's make our chart data realtime with ActionCable.

how it works:

open channel for data
broadcast event when data changes (create/update)
send new data back
update view js