@coins = { :ethereum => "$" }
@currency = 'USD'
@api_key = '581d0546-0927-4060-b4b0-eacc1a32d691'

@request_url = "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest?slug=#{@coins.keys.join(",")}"

@headers = {
   "Accepts"  => "application/json",
   "X-CMC_PRO_API_KEY" => @api_key
}
