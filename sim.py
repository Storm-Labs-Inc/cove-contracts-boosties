import random
from typing import Dict, List, NamedTuple
from collections import defaultdict

class Trade(object):
    sell_token: str
    buy_token: str
    sell_amount: float
    buy_amount: float
    value: float

    def __init__(self, sell_token, buy_token, sell_amount, buy_amount, value):
        self.sell_token = sell_token
        self.buy_token = buy_token
        self.sell_amount = sell_amount
        self.buy_amount = buy_amount
        self.value = value

    def __repr__(self):
        return f'Trade {self.sell_token} -> {self.buy_token}, {self.sell_amount} -> {self.buy_amount}, value: {self.value}'

# First, let's redefine the trade calculation to ensure that sellToken and buyToken are never None
class Basket:
    def __init__(self, name, token_preferences, target_weights):
        self.name = name
        self.token_preferences = token_preferences  # Tokens eligible to hold
        self.target_weights = target_weights  # Target weights for each token
        self.holdings = {token: 0 for token in token_preferences}  # Current holdings

    def __repr__(self):
        return f'Basket {self.name}'
    
    def calculate_sell_trades(self, prices):
        """
        Calculate the necessary sell trades for this basket to return to target allocation.
        :param prices: A dict with token prices
        :return: A list of sell trades required
        """
        # Calculate the total value of the basket
        total_value = sum(self.holdings[token] * prices[token] for token in self.holdings)
        
        # Determine the target value for each token
        target_values = {token: total_value * weight for token, weight in self.target_weights.items()}
        
        # Calculate the difference for each token to find out how much to sell
        trades = []
        for token, target_value in target_values.items():
            current_value = self.holdings[token] * prices[token]
            difference = target_value - current_value
            
            if difference < 0:
                # Need to sell this token
                trades.append(Trade(token, None, abs(difference) / prices[token], None, abs(difference)))
            else:
                # No trade needed
                continue
        
        return trades

    def calculate_buy_trades(self, prices):
        """
        Calculate the necessary buy trades for this basket to return to target allocation.
        :param prices: A dict with token prices
        :return: A list of buy trades required
        """
        # Calculate the total value of the basket
        total_value = sum(self.holdings[token] * prices[token] for token in self.holdings)
        
        # Determine the target value for each token
        target_values = {token: total_value * weight for token, weight in self.target_weights.items()}
        
        # Calculate the difference for each token to find out how much to buy
        trades = []
        for token, target_value in target_values.items():
            current_value = self.holdings[token] * prices[token]
            difference = target_value - current_value
            
            if difference > 0:
                # Need to buy this token
                trades.append(Trade(None, token, None, difference / prices[token], abs(difference)))
            else:
                # No trade needed
                continue
        
        return trades

    def calculate_trades(self, prices):
        """
        Calculate the necessary trades for this basket to return to target allocation,
        including both sellToken and buyToken for each trade.
        :param prices: A dict with token prices
        :return: A list of trades required
        """
        # Calculate the total value of the basket
        total_value = sum(self.holdings[token] * prices[token] for token in self.holdings)
        
        # Determine the target value for each token
        target_values = {token: total_value * weight for token, weight in self.target_weights.items()}
        
        # Calculate the difference for each token to find out how much to sell or buy
        trades = []
        sell_list = self.calculate_sell_trades(prices)
        buy_list = self.calculate_buy_trades(prices)
        
        # Generate trades by matching up buy and sell tokens and differences in value
        # If the values are the same, then the trade can be completed
        # If the values are different, then the trade with the smallest difference is completed
        i = 0
        while i < len(sell_list):
            j = 0
            while j < len(buy_list):
                sell_trade = sell_list[i]
                buy_trade = buy_list[j]

                if sell_trade.value == 0:
                    # Trade has already been completed
                    break
                
                if buy_trade.value == 0:
                    # Consider the next buy trade
                    j += 1
                    continue

                if sell_trade.value == buy_trade.value:
                    # Trade can be completed
                    trades.append(Trade(sell_trade.sell_token, buy_trade.buy_token, sell_trade.sell_amount, buy_trade.buy_amount, sell_trade.value))
                    sell_list[i].sell_amount = 0
                    sell_list[i].value = 0
                    buy_list[j].buy_amount = 0
                    buy_list[j].value = 0
                    break
                    
                elif sell_trade.value > buy_trade.value:
                    # Sell token has a larger value, so complete the buy trade and update the sell trade
                    partial_sell_amount = buy_trade.value / prices[sell_trade.sell_token]
                    trades.append(Trade(sell_trade.sell_token, buy_trade.buy_token, partial_sell_amount, buy_trade.buy_amount, buy_trade.value))
                    sell_list[i].sell_amount = sell_trade.sell_amount - partial_sell_amount
                    sell_list[i].value = sell_trade.value - buy_trade.value
                    buy_list[j].buy_amount = 0
                    buy_list[j].value = 0
                    j += 1
                    continue

                else:
                    # Buy token has a larger value, so complete the sell trade and update the buy trade
                    partial_buy_amount = sell_trade.value / prices[buy_trade.buy_token]
                    trades.append(Trade(sell_trade.sell_token, buy_trade.buy_token, sell_trade.sell_amount, partial_buy_amount, sell_trade.value))

                    buy_list[j].buy_amount = buy_trade.buy_amount - partial_buy_amount
                    buy_list[j].value = buy_trade.value - sell_trade.value
                    sell_list[i].sell_amount = 0
                    sell_list[i].value = 0
                    break

            i += 1

        return trades

# Function to simulate oracle prices
def mock_oracle_prices(tokens: List[str], price_range=(1.0, 1.1)) -> Dict[str, float]:
    """
    Generate mock prices for tokens in a given range.
    :param tokens: A list of token symbols
    :param price_range: A tuple representing the min and max price range
    :return: A dict with tokens as keys and prices as values
    """
    return {token: random.uniform(*price_range) for token in tokens}

# Define some tokens and their mock prices
tokens = ['yUSDT', 'yDAI', 'sFRAX', 'yUSDC']
oracle_prices = mock_oracle_prices(tokens)

# Create an example basket
basketA = Basket(name='A', token_preferences=tokens, target_weights={'yUSDT': 0.25, 'yDAI': 0.25, 'sFRAX': 0.25, 'yUSDC': 0.25})
basketA.holdings = {'yUSDT': 1000, 'yDAI': 200, 'sFRAX': 800, 'yUSDC': 500}  # Current holdings

# Calculate trades for basketA
trades_basketA = basketA.calculate_trades(oracle_prices)
# print trades
print('\nmatched trades')
for trade in trades_basketA:
    print(trade)