class ArticlesController < ApplicationController

  def index
    @article = Article.all
  end

  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      flash[:success] = "Article was successfully created"
    else
      render 'new'
    end
  end

  def show
    @article = Article.find(params[:id])
  end

  def edit
    @article = Article.find(params[:id])
  end

  def destroy
    @article = Article.find(params[:id])
    @article.destroy
    flash[:danger] = "Article succesfully destroyed"
    redirect_to articles_path
  end

  def update
    if @article.update(article_params)
      flash[:success] = "Article was succesfully updated "
      redirect_to article_path(@article)
    else
      render 'edit'
    end
    flash[:notice] = "Article succesfully updated"
  end

  private
  def article_params
    params.require(:article).permit(:title, :description)
  end
end