#!/bin/bash
# Run this in RDS Account CloudShell

echo "=== STEP 1: Test if proxy Lambda works ==="
cd rds
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
echo "Response:"
cat response.json
echo ""

echo "=== STEP 2: If response shows null, load data ==="
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"CREATE TABLE IF NOT EXISTS transactions (transaction_id INTEGER PRIMARY KEY, description VARCHAR(30))\"}"}' response.json
cat response.json
echo ""

aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"INSERT INTO transactions VALUES (10234567,'\''Online purchase at Amazon'\''),(20456789,'\''Gas station payment'\''),(30678901,'\''Grocery store checkout'\''),(40891234,'\''Restaurant dinner bill'\''),(50123456,'\''Monthly subscription fee'\''),(60345678,'\''ATM cash withdrawal'\''),(70567890,'\''Electric utility payment'\''),(80789012,'\''Coffee shop purchase'\''),(90901234,'\''Movie ticket booking'\''),(11223344,'\''Pharmacy medication buy'\''),(22334455,'\''Hotel accommodation charge'\''),(33445566,'\''Airline ticket purchase'\''),(44556677,'\''Car rental service'\''),(55667788,'\''Mobile phone bill payment'\''),(66778899,'\''Internet service charge'\''),(77889900,'\''Gym membership renewal'\''),(88990011,'\''Book store purchase'\''),(99001122,'\''Pet supplies shopping'\''),(12345678,'\''Home insurance premium'\''),(23456789,'\''Streaming service fee'\'') ON CONFLICT DO NOTHING\"}"}' response.json
cat response.json
echo ""

echo "=== STEP 3: Verify data loaded ==="
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
cat response.json
echo ""
echo "Expected: {\"statusCode\":200,\"body\":\"{\\\"10234567\\\": \\\"Online purchase at Amazon\\\"}\"}"
