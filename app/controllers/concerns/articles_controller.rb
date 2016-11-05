class ArticlesController < ApplicationController

  def index
    @article = Article.all
  end

  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    @article.save
    flash[:notice] = "Article was successfully created"
  end

  def show
    @article = Article.all
  end

  def edit
    @article = Article.find(params[:id])
  end

  def destroy
    #@article = Article.find(params[:id])
    #@article.destroy
    flash[:notice] = "Article succesfully destroyied"
  end

  private
  def article_params
    params.require(:article).permit(:title, :description)
  end
end