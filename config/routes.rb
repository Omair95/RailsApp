Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  root 'articles#home'
  get '/about', to: 'articles#about'

  #get '/articles/new', :to => 'articles#new', as: 'new_article'
  #get '/articles/:id/edit', :to => 'articles#edit', as: 'edit_article'
  #get '/articles/:id', :to => 'articles#show', as: 'articles'
  #patch '/articles/:id', :to => 'articles#update'
  #put '/articles/:id', :to => 'articles#update'
  #delete '/articles/:id', :to => 'articles#destroy'

  resources :articles
end
