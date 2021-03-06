Conductor.Routers = Conductor.Routers || {}


Conductor.Routers.Pools = Backbone.Router.extend({
  routes: {
    '': 'index',
    'pools:query': 'index',
    'pools/:id': 'show'
  },

  index: function() {
    setInterval(function() {
      var view = new Conductor.Views.PoolsIndex();

      if (view.currentView() == 'table') {
        switch(view.currentTab()) {
        case 'pools':
          view.collection = new Conductor.Models.Pools();
          break;
        case 'deployments':
          view.collection = new Conductor.Models.Deployments();
          break;
        case 'instances':
          view.collection = new Conductor.Models.Instances();
          break;
        default:
          return;
        }
      }
      else if (view.currentView() == 'pretty') {
        view.collection = new Conductor.Models.Deployments();
      }

      view.collection.queryParams = view.queryParams();
      view.collection.bind('change', function() { view.render() });

      view.collection.fetch({ success: function() {
        view.collection.trigger('change');
      }})

    }, Conductor.AJAX_REFRESH_INTERVAL);
  },

  show: function(id) {
    id = Conductor.idFromURLFragment(id);
    if(! _.isNumber(id)) return;

    setInterval(function() {
      var pool = new Conductor.Models.Pool({ id: id });
      var view = new Conductor.Views.PoolsShow({ model: pool });

      if(view.currentTab() !== 'deployments') return;

      pool.fetch({ success: function() { view.render(); } })
    }, Conductor.AJAX_REFRESH_INTERVAL);
  }
});


Conductor.Routers.Deployments = Backbone.Router.extend({
  routes: {
    'deployments': 'index',
    'deployments/:id': 'show'
  },

  index: function() {
  },

  show: function(id) {
    id = Conductor.idFromURLFragment(id);
    if(! _.isNumber(id)) return;

    setInterval(function() {
      var deployment = new Conductor.Models.Deployment({ id: id });
      var view = new Conductor.Views.DeploymentsShow({ model: deployment,
        collection: deployment.instances });

      if(view.currentTab() !== 'instances') return;

      deployment.bind('change', function() { view.render() });

      deployment.instances.fetch({success: function(instances) {
        deployment.change();
      } })
    }, Conductor.AJAX_REFRESH_INTERVAL);
  }
});
