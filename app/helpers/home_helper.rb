module HomeHelper
  # Lê os arquivos direto de app/assets/images/admin/clients (qualquer
  # extensão) pra não precisar mexer em código toda vez que um logo de
  # cliente novo for adicionado/removido — só soltar o arquivo na pasta.
  def client_logo_assets
    dir = Rails.root.join('app', 'assets', 'images', 'admin', 'clients')
    Dir.glob(dir.join('*'))
       .select { |path| File.file?(path) }
       .sort
       .map { |path| "admin/clients/#{File.basename(path)}" }
  end
end
