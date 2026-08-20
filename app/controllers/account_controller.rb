class AccountController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    if current_user.update(account_params)
      redirect_to edit_account_path, notice: 'Dados atualizados com sucesso.'
    else
      @user = current_user
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation)
  end
end
